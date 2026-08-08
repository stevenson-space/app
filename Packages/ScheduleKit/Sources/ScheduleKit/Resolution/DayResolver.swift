import Foundation

/// Everything `resolveDay` reads. Pure data in, pure data out — no clocks,
/// no storage, no network — so every surface computes identical answers and
/// tests can drive any date deterministically.
public struct ResolverInputs: Sendable {
    public var map: DayTypeMap?
    public var overrides: [DayKey: DayOverride]
    public var config: UserConfig
    public var catalog: BellScheduleCatalog
    public var years: [SchoolYear]

    public init(map: DayTypeMap? = nil,
                overrides: [DayKey: DayOverride] = [:],
                config: UserConfig = UserConfig(),
                catalog: BellScheduleCatalog,
                years: [SchoolYear] = SchoolYearCatalog.years) {
        self.map = map
        self.overrides = overrides
        self.config = config
        self.catalog = catalog
        self.years = years
    }
}

/// Resolution priority:
/// 1. Manual override for the date
/// 2. Remote map entry (wins even outside school-year bounds — summer sessions)
/// 3. Outside school year → no regular schedule (never defaults to Standard)
/// 4. Bundled break range → break
/// 5. Weekend
/// 6. In-session weekday → Standard, by design (not a guess)
public func resolveDay(_ day: DayKey,
                       inputs: ResolverInputs,
                       calendar: Calendar = SchoolTime.calendar) -> DayTimeline {
    let year = inputs.years.first { $0.contains(day) }
    let labeledDay = year?.labeledDays[day]

    // 1. Manual override.
    if let override = inputs.overrides[day] {
        switch override.type {
        case .bell(let family, let rotation):
            let uncertain = family == .earlyDismissal && rotation == nil
            return schoolTimeline(day: day, family: family, rotation: rotation,
                                  provenance: .override, rotationUncertain: uncertain,
                                  labeledDay: labeledDay, inputs: inputs, calendar: calendar)
        case .noSchool:
            return bareTimeline(day: day, kind: .noSchool, label: "No School",
                                note: labeledDay, provenance: .override)
        case .asynchronous:
            return bareTimeline(day: day, kind: .asynchronous, label: "Asynchronous E-Learning Day",
                                note: labeledDay, provenance: .override)
        }
    }

    // 2. Remote map.
    if let match = inputs.map?.match(day) {
        switch match.family {
        case .bell(let family):
            var rotation: EDRotation? = nil
            var uncertain = false
            if family == .earlyDismissal {
                (rotation, uncertain) = inferEDRotation(day: day, span: match.span, calendar: calendar)
            }
            return schoolTimeline(day: day, family: family, rotation: rotation,
                                  provenance: .remoteMap, rotationUncertain: uncertain,
                                  labeledDay: labeledDay, inputs: inputs, calendar: calendar)
        case .noSchool:
            return bareTimeline(day: day, kind: .noSchool, label: "No School",
                                note: labeledDay, provenance: .remoteMap)
        case .asynchronous:
            return bareTimeline(day: day, kind: .asynchronous, label: "Asynchronous E-Learning Day",
                                note: labeledDay, provenance: .remoteMap)
        case .unknown(let rawKey):
            return bareTimeline(day: day, kind: .unknownType(name: rawKey), label: rawKey,
                                note: labeledDay, provenance: .remoteMap)
        }
    }

    // 3. Outside the school year: never Standard.
    guard let year else {
        return bareTimeline(day: day, kind: .outsideYear, label: "Summer Break",
                            note: nil, provenance: .outsideYear)
    }

    // 4. Bundled breaks.
    if let schoolBreak = year.breakContaining(day) {
        return bareTimeline(day: day, kind: .breakDay(label: schoolBreak.label),
                            label: schoolBreak.label, note: nil, provenance: .bundledBreak)
    }

    // 5. Weekend.
    if day.isWeekend {
        return bareTimeline(day: day, kind: .weekend, label: "Weekend",
                            note: nil, provenance: .weekend)
    }

    // 6. Unlisted in-session weekday: Standard by design.
    return schoolTimeline(day: day, family: .standard, rotation: nil,
                          provenance: .defaultStandard, rotationUncertain: false,
                          labeledDay: labeledDay, inputs: inputs, calendar: calendar)
}

/// Finals rotation from a date's position in its map span, counting school
/// weekdays only. Ordinal 0 → rotation 1, ordinal 1 → rotation 2; deeper
/// ordinals alternate by parity but are flagged uncertain, as is a standalone
/// single date (no range to infer from).
func inferEDRotation(day: DayKey, span: DateSpan, calendar: Calendar) -> (EDRotation?, Bool) {
    guard !span.isSingleDay else { return (.rotation1, true) }
    let weekdays = span.days(calendar: calendar).filter { !$0.isWeekend }
    guard let ordinal = weekdays.firstIndex(of: day) else {
        // A weekend date inside an ED span — data oddity; stay honest.
        return (.rotation1, true)
    }
    let rotation: EDRotation = ordinal.isMultiple(of: 2) ? .rotation1 : .rotation2
    return (rotation, ordinal >= 2)
}

// MARK: - Timeline construction

private func bareTimeline(day: DayKey, kind: DayKind, label: String,
                          note: String?, provenance: Provenance) -> DayTimeline {
    DayTimeline(day: day, kind: kind, family: nil, rotation: nil,
                scheduleLabel: label, dayNote: note, provenance: provenance,
                rotationUncertain: false, blocks: [], moments: [])
}

private func schoolTimeline(day: DayKey, family: BellFamily, rotation: EDRotation?,
                            provenance: Provenance, rotationUncertain: Bool,
                            labeledDay: String?, inputs: ResolverInputs,
                            calendar: Calendar) -> DayTimeline {
    guard let schedule = inputs.catalog.schedule(family: family, rotation: rotation) else {
        // A bell family with no bundled table is a data bug; degrade honestly.
        return bareTimeline(day: day, kind: .unknownType(name: family.displayName),
                            label: family.displayName, note: labeledDay, provenance: provenance)
    }

    let blocks = personalizedBlocks(schedule: schedule, config: inputs.config,
                                    day: day, calendar: calendar)
    let notes = [labeledDay, schedule.rotation?.shortName].compactMap(\.self)

    return DayTimeline(
        day: day,
        kind: .school,
        family: family,
        rotation: schedule.rotation,
        scheduleLabel: schedule.displayName,
        dayNote: notes.isEmpty ? nil : notes.joined(separator: " · "),
        provenance: provenance,
        rotationUncertain: rotationUncertain,
        blocks: blocks,
        moments: buildMoments(from: blocks))
}

// MARK: - Personalization

/// Applies the user's lunch/advisory assignment, free periods, and custom
/// names to a bell table for a specific day, producing concrete instants.
func personalizedBlocks(schedule: BellSchedule, config rawConfig: UserConfig,
                        day: DayKey, calendar: Calendar) -> [ResolvedBlock] {
    // Advisory (freshman) doesn't meet on Fridays; the period it shares with
    // lunch becomes a full-period lunch. Resolve it here so Home and the
    // notification planner see the same shape (no phantom advisory half, no
    // advisory-ending alert).
    let config = fridayAdvisoryAdjusted(rawConfig, day: day, calendar: calendar)
    var resolved: [ResolvedBlock] = []

    for block in schedule.fullBlocks {
        guard let number = block.id.periodNumber else {
            resolved.append(contentsOf: makeBlocks(for: block, role: specialRole(block.id),
                                                   config: config, day: day, calendar: calendar))
            continue
        }

        let lunchHere = config.lunch?.basePeriod == number ? config.lunch : nil
        let advisoryHere = config.advisory?.basePeriod == number ? config.advisory : nil

        // Full-period assignments (or A/B assignments on days with no A/B
        // tables) take the whole period. Lunch wins any misconfigured tie.
        let halves = schedule.abBlocks(forPeriod: number)
        let canSplit = halves.count == 2

        if let lunch = lunchHere, lunch.choice == .full || !canSplit {
            resolved.append(contentsOf: makeBlocks(for: block, role: .lunch,
                                                   config: config, day: day, calendar: calendar))
            continue
        }
        if let advisory = advisoryHere, lunchHere == nil, advisory.choice == .full || !canSplit {
            resolved.append(contentsOf: makeBlocks(for: block, role: .advisory,
                                                   config: config, day: day, calendar: calendar))
            continue
        }

        if canSplit, lunchHere != nil || advisoryHere != nil {
            for halfBlock in halves {
                let role = halfRole(half: halfBlock.half, lunch: lunchHere,
                                    advisory: advisoryHere, number: number, config: config)
                resolved.append(contentsOf: makeBlocks(for: halfBlock, role: role,
                                                       config: config, day: day, calendar: calendar))
            }
            continue
        }

        let role: BlockRole = config.freePeriods.contains(number) ? .free : .classPeriod
        resolved.append(contentsOf: makeBlocks(for: block, role: role,
                                               config: config, day: day, calendar: calendar))
    }

    return resolved
}

/// Advisory doesn't meet on Fridays: drop it and expand the paired lunch to the
/// whole shared period. Other weekdays and non-advisory configs pass through
/// untouched. Only the resolved timeline changes — the stored config is intact.
func fridayAdvisoryAdjusted(_ config: UserConfig, day: DayKey, calendar: Calendar) -> UserConfig {
    // Gregorian weekday: Sunday = 1 … Friday = 6 … Saturday = 7.
    guard let advisory = config.advisory,
          day.weekday(calendar: calendar) == 6 else { return config }
    var adjusted = config
    adjusted.advisory = nil
    adjusted.lunch = SplitAssignment(basePeriod: advisory.basePeriod, choice: .full)
    return adjusted
}

private func halfRole(half: Half?, lunch: SplitAssignment?, advisory: SplitAssignment?,
                      number: Int, config: UserConfig) -> BlockRole {
    if let half {
        if let lunch, lunch.choice.matches(half) { return .lunch }
        if let advisory, advisory.choice.matches(half) { return .advisory }
    }
    return config.freePeriods.contains(number) ? .free : .classPeriod
}

private extension HalfChoice {
    /// Whether this placement occupies the given A/B half. `.full` matches
    /// neither — it's resolved before halves are considered.
    func matches(_ half: Half) -> Bool {
        switch (self, half) {
        case (.a, .a), (.b, .b): return true
        default: return false
        }
    }
}

private func specialRole(_ id: PeriodID) -> BlockRole {
    switch id {
    case .homeroom: return .homeroom
    case .activity: return .activity
    case .assembly: return .assembly
    case .makeup: return .makeup
    case .summer: return .summerSchool
    case .period: return .classPeriod
    }
}

private func makeBlocks(for block: Block, role: BlockRole, config: UserConfig,
                        day: DayKey, calendar: Calendar) -> [ResolvedBlock] {
    guard let start = day.date(at: block.start, calendar: calendar),
          let end = day.date(at: block.end, calendar: calendar),
          start < end else { return [] }

    let customization = config.customization(for: block.id)
    let displayName: String
    let room: String?
    switch role {
    case .lunch:
        displayName = "Lunch"
        room = nil
    case .advisory:
        displayName = "Advisory"
        room = nil
    case .free:
        displayName = customization?.name?.nilIfEmpty ?? "Free Period"
        room = nil
    default:
        displayName = customization?.name?.nilIfEmpty ?? block.id.defaultDisplayName
        room = customization?.room?.nilIfEmpty
    }

    let id = block.id.storageKey + (block.half?.rawValue ?? "")
    return [ResolvedBlock(id: id, periodID: block.id, half: block.half, role: role,
                          displayName: displayName, room: room, start: start, end: end)]
}

// MARK: - Moment building

/// Collapses each run of consecutive free blocks (and the gaps between them)
/// into a single span, so "Free until 1:46 PM" replaces counting down an
/// unattended class. The trailing gap before the next attended block stays a
/// normal passing period.
func buildMoments(from blocks: [ResolvedBlock]) -> [ResolvedSpan] {
    var moments: [ResolvedSpan] = []
    var index = 0

    while index < blocks.count {
        let block = blocks[index]
        if block.role == .free {
            var run = [block]
            while index + 1 < blocks.count, blocks[index + 1].role == .free {
                index += 1
                run.append(blocks[index])
            }
            let first = run.first!
            let last = run.last!
            moments.append(ResolvedSpan(
                id: run.map(\.id).joined(separator: "+"),
                role: .free,
                displayName: run.count == 1 ? first.displayName : "Free",
                room: nil,
                start: first.start,
                end: last.end,
                periodID: run.count == 1 ? first.periodID : nil,
                half: run.count == 1 ? first.half : nil,
                blockIDs: run.map(\.id)))
        } else {
            moments.append(ResolvedSpan(
                id: block.id,
                role: block.role,
                displayName: block.displayName,
                room: block.room,
                start: block.start,
                end: block.end,
                periodID: block.periodID,
                half: block.half,
                blockIDs: [block.id]))
        }
        index += 1
    }

    return moments
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
