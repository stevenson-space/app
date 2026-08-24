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

// MARK: - Standard-day template

/// The student's personalized *standard* day, independent of any real date —
/// what the schedule editor shows and edits. Materialized on a fixed reference
/// Monday so advisory is not Friday-collapsed; only the wall-clock components
/// of the returned blocks are meaningful.
public func standardTemplate(config: UserConfig,
                             catalog: BellScheduleCatalog,
                             calendar: Calendar = SchoolTime.calendar) -> [ResolvedBlock] {
    guard let schedule = catalog.schedule(family: .standard, rotation: nil) else { return [] }
    // 2001-01-01 is a Monday.
    let referenceMonday = DayKey(year: 2001, month: 1, day: 1)
    return personalizedBlocks(schedule: schedule, config: config,
                              day: referenceMonday, calendar: calendar)
}

// MARK: - Personalization

/// Applies the user's period plans (classes, 1½-period extensions, lunch,
/// advisory, free halves) and custom names to a bell table for a specific day,
/// producing concrete instants.
///
/// On splittable schedules, contiguous class slots sharing an anchor merge
/// into one block (chemistry 2–3A is one continuous class; the internal bell
/// doesn't apply to it). Schedules without A/B tables resolve one block per
/// period with the safe-direction precedence `lunch > advisory > class > free`,
/// and never merge — on a finals day the app can't know which slot hosts a
/// 1½-period class's final.
func personalizedBlocks(schedule: BellSchedule, config rawConfig: UserConfig,
                        day: DayKey, calendar: Calendar) -> [ResolvedBlock] {
    // Advisory (freshman) doesn't meet on Fridays; its slots become lunch, so
    // a paired period collapses to one full-period lunch. Resolve it here so
    // Home and the notification planner see the same shape.
    let config = fridayAdvisoryAdjusted(rawConfig, day: day, calendar: calendar)
    var resolved: [ResolvedBlock] = []
    // Run of contiguous class slots sharing one anchor, awaiting merge.
    var pendingRun: [(block: Block, anchor: Int)] = []

    func flushRun() {
        if let block = makeClassBlock(run: pendingRun, config: config,
                                      day: day, calendar: calendar) {
            resolved.append(block)
        }
        pendingRun = []
    }

    func appendToRun(_ block: Block, anchor: Int) {
        if let last = pendingRun.last, last.anchor != anchor {
            flushRun()
        }
        pendingRun.append((block, anchor))
    }

    func emit(_ block: Block, role: BlockRole, namingID: PeriodID? = nil) {
        flushRun()
        if let made = makeBlock(for: block, role: role, namingID: namingID,
                                config: config, day: day, calendar: calendar) {
            resolved.append(made)
        }
    }

    for block in schedule.fullBlocks {
        guard let number = block.id.periodNumber else {
            emit(block, role: specialRole(block.id))
            continue
        }

        let plan = config.plan(for: number)
        let halves = schedule.abBlocks(forPeriod: number)

        guard halves.count == 2 else {
            // No A/B tables: one block, precedence lunch > advisory > class > free.
            if plan.a == .lunch || plan.b == .lunch {
                emit(block, role: .lunch)
            } else if plan.a == .advisory || plan.b == .advisory {
                emit(block, role: .advisory)
            } else if let anchor = plan.a.classAnchor ?? plan.b.classAnchor {
                emit(block, role: .classPeriod, namingID: .period(anchor))
            } else {
                emit(block, role: .free)
            }
            continue
        }

        if plan.isUniform {
            // Both halves agree: the whole period is one thing, at the full
            // block's times (which already span the internal gap).
            switch plan.a {
            case .classSlot(let anchor): appendToRun(block, anchor: anchor)
            case .lunch: emit(block, role: .lunch)
            case .advisory: emit(block, role: .advisory)
            case .free: emit(block, role: .free)
            }
            continue
        }

        for halfBlock in halves {
            guard let half = halfBlock.half else { continue }
            switch plan.slot(half) {
            case .classSlot(let anchor): appendToRun(halfBlock, anchor: anchor)
            case .lunch: emit(halfBlock, role: .lunch)
            case .advisory: emit(halfBlock, role: .advisory)
            case .free: emit(halfBlock, role: .free)
            }
        }
    }

    flushRun()
    return resolved
}

/// Advisory doesn't meet on Fridays: every advisory slot becomes lunch, so the
/// paired half-lunch expands to the whole shared period. Other weekdays and
/// non-advisory configs pass through untouched. Only the resolved timeline
/// changes — the stored config is intact.
func fridayAdvisoryAdjusted(_ config: UserConfig, day: DayKey, calendar: Calendar) -> UserConfig {
    // Gregorian weekday: Sunday = 1 … Friday = 6 … Saturday = 7.
    guard day.weekday(calendar: calendar) == 6 else { return config }
    var adjusted = config
    for period in UserConfig.periodRange {
        var plan = adjusted.plan(for: period)
        var changed = false
        if plan.a == .advisory { plan.a = .lunch; changed = true }
        if plan.b == .advisory { plan.b = .lunch; changed = true }
        if changed { adjusted.setPlan(plan, for: period) }
    }
    return adjusted
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

/// The display id of one bell-table row ("4", "4A").
private func rowID(_ block: Block) -> String {
    block.id.storageKey + (block.half?.rawValue ?? "")
}

/// One or more contiguous class rows sharing an anchor → a single block. A
/// one-row run reproduces the legacy shape exactly (id "4" or "4B"); a longer
/// run spans from the first row's start to the last row's end, absorbing the
/// internal passing gaps the student sits through.
private func makeClassBlock(run: [(block: Block, anchor: Int)], config: UserConfig,
                            day: DayKey, calendar: Calendar) -> ResolvedBlock? {
    guard let first = run.first, let last = run.last,
          let start = day.date(at: first.block.start, calendar: calendar),
          let end = day.date(at: last.block.end, calendar: calendar),
          start < end else { return nil }

    let anchorID = PeriodID.period(first.anchor)
    let customization = config.customization(for: anchorID)
    let id = run.map { rowID($0.block) }.joined(separator: "+")
    let spanLabel: String?
    let half: Half?
    if run.count == 1 {
        spanLabel = first.block.half.map { _ in rowID(first.block) }
        half = first.block.half
    } else {
        spanLabel = "\(rowID(first.block))–\(rowID(last.block))"
        half = nil
    }

    return ResolvedBlock(
        id: id, periodID: anchorID, half: half, role: .classPeriod,
        displayName: customization?.name?.nilIfEmpty ?? anchorID.defaultDisplayName,
        room: customization?.room?.nilIfEmpty,
        spanLabel: spanLabel, start: start, end: end)
}

/// A single non-class row. `namingID` overrides which period's customization
/// names the block (a class period on a non-splittable day is named after the
/// class's anchor, not its own number).
private func makeBlock(for block: Block, role: BlockRole, namingID: PeriodID? = nil,
                       config: UserConfig, day: DayKey, calendar: Calendar) -> ResolvedBlock? {
    guard let start = day.date(at: block.start, calendar: calendar),
          let end = day.date(at: block.end, calendar: calendar),
          start < end else { return nil }

    let customization = config.customization(for: namingID ?? block.id)
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
        // Free time is anonymous. A stored name belongs to the period's class
        // (kept for when the period becomes a class again) and never leaks
        // onto the free block.
        displayName = "Free Period"
        room = nil
    default:
        displayName = customization?.name?.nilIfEmpty ?? (namingID ?? block.id).defaultDisplayName
        room = customization?.room?.nilIfEmpty
    }

    return ResolvedBlock(id: rowID(block), periodID: block.id,
                         customizationID: namingID, half: block.half,
                         role: role, displayName: displayName, room: room,
                         spanLabel: block.half.map { _ in rowID(block) },
                         start: start, end: end)
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
