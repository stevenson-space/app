import Foundation

public enum TimeFormatPref: String, Codable, CaseIterable, Sendable {
    case system
    case twelveHour
    case twentyFourHour

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .twelveHour: return "12-hour"
        case .twentyFourHour: return "24-hour"
        }
    }
}

public enum AppearancePref: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Which colour identity the app's chrome wears. Purely cosmetic — it never
/// touches the semantic colours that flag an abnormal schedule.
public enum ThemePref: String, Codable, CaseIterable, Sendable {
    /// Stevenson green and gold.
    case stevenson
    /// The stock iOS palette the app shipped with.
    case classic

    public var displayName: String {
        switch self {
        case .stevenson: return "Stevenson"
        case .classic: return "Classic"
        }
    }
}

public struct PeriodCustomization: Codable, Equatable, Sendable {
    public var name: String?
    public var room: String?
    /// User-chosen card icon; nil falls back to a role/subject default.
    public var emoji: String?

    public init(name: String? = nil, room: String? = nil, emoji: String? = nil) {
        self.name = name
        self.room = room
        self.emoji = emoji
    }

    public var isEmpty: Bool {
        (name?.isEmpty ?? true) && (room?.isEmpty ?? true) && (emoji?.isEmpty ?? true)
    }
}

/// Where a lunch/advisory assignment sits: which numbered period, and whether
/// it occupies the A half, B half, or the full period. On days whose schedule
/// has no A/B subdivisions, an A/B choice falls back to the full period.
public struct SplitAssignment: Codable, Equatable, Hashable, Sendable {
    public var basePeriod: Int
    public var choice: HalfChoice

    public init(basePeriod: Int, choice: HalfChoice) {
        self.basePeriod = basePeriod
        self.choice = choice
    }

    public var displayName: String {
        choice == .full ? "Period \(basePeriod)" : "\(basePeriod)\(choice.rawValue)"
    }
}

public struct UserConfig: Equatable, Sendable {
    public static let periodRange = 1...8
    /// The periods a lunch wave (and thus advisory) can occupy.
    public static let advisoryPeriods = 4...6

    /// The single source of truth for the student's day: what each half of
    /// each numbered period holds. Sparse — a missing entry means a
    /// full-period class anchored at the period itself.
    public private(set) var periodPlans: [Int: PeriodPlan]
    /// Keyed by `PeriodID.storageKey` of a class's *anchor* — identity, never
    /// position, so names survive finals reordering and 1½-period spans.
    public var customizations: [String: PeriodCustomization]
    public var timeFormat: TimeFormatPref
    public var appearance: AppearancePref
    public var theme: ThemePref

    /// Grid-first designated initializer. Out-of-range keys and entries equal
    /// to the default plan are dropped so the sparse form stays canonical and
    /// `Equatable` means what it says.
    public init(periodPlans: [Int: PeriodPlan],
                customizations: [String: PeriodCustomization] = [:],
                timeFormat: TimeFormatPref = .system,
                appearance: AppearancePref = .system,
                theme: ThemePref = .stevenson) {
        self.periodPlans = periodPlans.filter {
            Self.periodRange.contains($0.key) && !$0.value.isStandardClass(for: $0.key)
        }
        self.customizations = customizations
        self.timeFormat = timeFormat
        self.appearance = appearance
        self.theme = theme
    }

    /// Legacy-shaped initializer; builds the grid from the old exception
    /// fields. Paint order (free → advisory → lunch) reproduces the historic
    /// "lunch wins any misconfigured tie" rule.
    public init(lunch: SplitAssignment? = nil,
                advisory: SplitAssignment? = nil,
                freePeriods: Set<Int> = [],
                customizations: [String: PeriodCustomization] = [:],
                timeFormat: TimeFormatPref = .system,
                appearance: AppearancePref = .system,
                theme: ThemePref = .stevenson) {
        self.init(periodPlans: [:], customizations: customizations,
                  timeFormat: timeFormat, appearance: appearance, theme: theme)
        self.freePeriods = freePeriods
        self.advisory = advisory
        self.lunch = lunch
    }

    public func customization(for id: PeriodID) -> PeriodCustomization? {
        customizations[id.storageKey]
    }

    // MARK: - Grid access

    public func plan(for period: Int) -> PeriodPlan {
        periodPlans[period] ?? .standardClass(period)
    }

    /// Stores a plan, keeping the dictionary sparse/canonical.
    public mutating func setPlan(_ plan: PeriodPlan, for period: Int) {
        guard Self.periodRange.contains(period) else { return }
        if plan.isStandardClass(for: period) {
            periodPlans.removeValue(forKey: period)
        } else {
            periodPlans[period] = plan
        }
    }

    public mutating func setSlot(period: Int, half: Half, to new: HalfSlotAssignment) {
        guard Self.periodRange.contains(period) else { return }
        var plan = plan(for: period)
        plan.setSlot(half, new)
        setPlan(plan, for: period)
    }

    /// Marks the class anchored at `anchor` as 1½ periods (claiming the next
    /// period's A half) or retracts that claim. Retraction only touches a slot
    /// that actually points back at the anchor.
    public mutating func setClassExtended(anchor: Int, _ extended: Bool) {
        let next = anchor + 1
        guard Self.periodRange.contains(anchor), Self.periodRange.contains(next) else { return }
        if extended {
            setSlot(period: next, half: .a, to: .classSlot(anchor: anchor))
        } else if plan(for: next).a == .classSlot(anchor: anchor) {
            setSlot(period: next, half: .a, to: .classSlot(anchor: next))
        }
    }

    /// Marks the class anchored at `anchor` as starting a half period early
    /// (claiming the previous period's B half) or retracts that claim.
    /// Claiming refuses to displace lunch or advisory; claiming out of a full
    /// class displaces that class entirely (its A half becomes free) so no
    /// phantom half class is left behind. Retracting frees the claimed half.
    public mutating func setClassStartsEarly(anchor: Int, _ startsEarly: Bool) {
        let previous = anchor - 1
        guard Self.periodRange.contains(anchor), Self.periodRange.contains(previous) else { return }
        var plan = plan(for: previous)
        if startsEarly {
            guard plan.b != .lunch && plan.b != .advisory else { return }
            let displacesNeighborClass = plan.b == .classSlot(anchor: previous)
            let ownAWasNeighborClaim = self.plan(for: anchor).a == .classSlot(anchor: previous)
            if plan.a == .classSlot(anchor: previous) { plan.a = .free }
            plan.b = .classSlot(anchor: anchor)
            setPlan(plan, for: previous)
            if displacesNeighborClass {
                // The displaced class's own 1½-period claims must not dangle…
                retractClassClaims(anchor: previous)
                // …and if one of them was our own A half, it belongs to this
                // class now — keep the span contiguous instead of free.
                if ownAWasNeighborClaim {
                    setSlot(period: anchor, half: .a, to: .classSlot(anchor: anchor))
                }
            }
        } else if plan.b == .classSlot(anchor: anchor) {
            plan.b = .free
            setPlan(plan, for: previous)
        }
    }

    /// How long the class anchored at `anchor` currently runs.
    public func classLength(anchor: Int) -> ClassLength {
        if anchor < Self.periodRange.upperBound,
           plan(for: anchor + 1).a == .classSlot(anchor: anchor) { return .extendsForward }
        if anchor > Self.periodRange.lowerBound,
           plan(for: anchor - 1).b == .classSlot(anchor: anchor) { return .startsEarly }
        return .standard
    }

    /// The one entry point for changing a class's length. Retracting a claim
    /// settles the vacated half sensibly: a leftover lunch expands to the
    /// whole period (ready for the advisory toggle), a leftover free half
    /// restores the neighbor's full class (or leaves a fully free period
    /// free). Extending displaces a phantom own-class leftover to free and
    /// retracts any onward claims the displaced class held.
    public mutating func setClassLength(anchor: Int, _ new: ClassLength) {
        guard Self.periodRange.contains(anchor), classLength(anchor: anchor) != new else { return }

        let next = anchor + 1
        if Self.periodRange.contains(next), plan(for: next).a == .classSlot(anchor: anchor) {
            setClassExtended(anchor: anchor, false)
            switch plan(for: next).b {
            case .free:
                setPlan(.standardClass(next), for: next)
            case .lunch:
                lunch = SplitAssignment(basePeriod: next, choice: .full)
            default:
                break
            }
        }
        let previous = anchor - 1
        if Self.periodRange.contains(previous), plan(for: previous).b == .classSlot(anchor: anchor) {
            setClassStartsEarly(anchor: anchor, false)
            if plan(for: previous).a == .lunch {
                lunch = SplitAssignment(basePeriod: previous, choice: .full)
            }
        }

        switch new {
        case .extendsForward:
            guard Self.periodRange.contains(next) else { return }
            let nextPlan = plan(for: next)
            if nextPlan == PeriodPlan(a: .lunch, b: .lunch) {
                // A full-period lunch makes way by shrinking to its B half.
                lunch = SplitAssignment(basePeriod: next, choice: .b)
            } else if nextPlan.a == .lunch || nextPlan.a == .advisory {
                // Never displace a half lunch or advisory (the UI blocks this).
                return
            }
            setClassExtended(anchor: anchor, true)
            if plan(for: next).b == .classSlot(anchor: next) {
                setSlot(period: next, half: .b, to: .free)
                retractClassClaims(anchor: next)
            }
        case .startsEarly:
            guard Self.periodRange.contains(previous) else { return }
            if plan(for: previous) == PeriodPlan(a: .lunch, b: .lunch) {
                // A full-period lunch makes way by shrinking to its A half.
                lunch = SplitAssignment(basePeriod: previous, choice: .a)
            }
            setClassStartsEarly(anchor: anchor, true)
        case .standard:
            break
        }
    }

    /// Frees every adjacent half still pointing at `anchor` — used when the
    /// anchor period stops being a class (turned into lunch or free) so its
    /// 1½-period claims don't dangle.
    public mutating func retractClassClaims(anchor: Int) {
        let claim = HalfSlotAssignment.classSlot(anchor: anchor)
        for period in [anchor - 1, anchor + 1] where Self.periodRange.contains(period) {
            var plan = plan(for: period)
            var changed = false
            if plan.a == claim { plan.a = .free; changed = true }
            if plan.b == claim { plan.b = .free; changed = true }
            if changed { setPlan(plan, for: period) }
        }
    }

    // MARK: - Derived legacy views (read and write the grid)

    public var lunch: SplitAssignment? {
        get { derivedAssignment(of: .lunch) }
        set { paint(role: .lunch, to: newValue) }
    }

    public var advisory: SplitAssignment? {
        get { derivedAssignment(of: .advisory) }
        set { paint(role: .advisory, to: newValue) }
    }

    /// Periods that are entirely free. (A half-free period next to a lunch
    /// wave or a 1½-period class is visible in `plan(for:)`, not here.)
    public var freePeriods: Set<Int> {
        get {
            Set(Self.periodRange.filter { plan(for: $0) == PeriodPlan(a: .free, b: .free) })
        }
        set {
            let current = freePeriods
            for period in newValue.subtracting(current) {
                // If this period anchors a 1½-period class, freeing the
                // anchor must also remove its continuation next door.
                retractClassClaims(anchor: period)
                setPlan(PeriodPlan(a: .free, b: .free), for: period)
            }
            for period in current.subtracting(newValue) {
                setPlan(.standardClass(period), for: period)
            }
        }
    }

    private func derivedAssignment(of slot: HalfSlotAssignment) -> SplitAssignment? {
        for period in Self.periodRange {
            let plan = plan(for: period)
            switch (plan.a == slot, plan.b == slot) {
            case (true, true): return SplitAssignment(basePeriod: period, choice: .full)
            case (true, false): return SplitAssignment(basePeriod: period, choice: .a)
            case (false, true): return SplitAssignment(basePeriod: period, choice: .b)
            case (false, false): continue
            }
        }
        return nil
    }

    /// Repaints where `role` lives, then the new assignment (if any) claims
    /// its slots — overwriting whatever held them. A vacated full period
    /// becomes the period's class again; a vacated half becomes free, unless
    /// the other half already holds the period's own class (then the full
    /// class is restored rather than leaving a phantom half). Lunch leaving
    /// an advisory pairing dissolves the advisory too — advisory never exists
    /// without lunch in the other half — so the fully vacated period also
    /// reverts to its class.
    private mutating func paint(role: HalfSlotAssignment, to new: SplitAssignment?) {
        for period in Self.periodRange {
            var plan = plan(for: period)
            if plan.a == role && plan.b == role {
                setPlan(.standardClass(period), for: period)
                continue
            }
            if role == .lunch,
               plan.a == role || plan.b == role,
               plan.a == .advisory || plan.b == .advisory {
                setPlan(.standardClass(period), for: period)
                continue
            }
            let ownClass = HalfSlotAssignment.classSlot(anchor: period)
            var changed = false
            if plan.a == role {
                plan.a = plan.b == ownClass ? ownClass : .free
                changed = true
            }
            if plan.b == role {
                plan.b = plan.a == ownClass ? ownClass : .free
                changed = true
            }
            if changed { setPlan(plan, for: period) }
        }
        guard let new, Self.periodRange.contains(new.basePeriod) else { return }
        var plan = plan(for: new.basePeriod)
        switch new.choice {
        case .full:
            plan.a = role
            plan.b = role
        case .a:
            plan.a = role
        case .b:
            plan.b = role
        }
        setPlan(plan, for: new.basePeriod)
        // The claimed slots may have held the period's own class; once no own
        // slot remains, any 1½-period claims that class held next door are
        // stale and would render as phantom continuations.
        let own = HalfSlotAssignment.classSlot(anchor: new.basePeriod)
        if plan.a != own && plan.b != own {
            retractClassClaims(anchor: new.basePeriod)
        }
    }
}

extension UserConfig {
    /// Advisory (freshmen only) is never placed independently: it occupies one
    /// half of one of the lunch periods (4–6), and lunch automatically takes
    /// the other half of the same period. Advisory 4A ⇒ lunch 4B, advisory
    /// 5B ⇒ lunch 5A, and so on. This is the only way advisory gets set.
    public mutating func setPairedAdvisory(basePeriod: Int, advisoryHalf: Half) {
        // Advisory/lunch only live in periods 4–6; ignore out-of-range requests
        // rather than persisting an impossible placement.
        guard Self.advisoryPeriods.contains(basePeriod) else { return }
        // Lunch repaints first: moving it dissolves any old pairing (reverting
        // that period to its class); advisory then claims its half.
        lunch = SplitAssignment(basePeriod: basePeriod,
                                choice: advisoryHalf == .a ? .b : .a)
        advisory = SplitAssignment(basePeriod: basePeriod,
                                   choice: advisoryHalf == .a ? .a : .b)
    }

    /// Turning advisory off keeps the derived lunch half as a plain lunch
    /// selection — the student still eats at the same time.
    public mutating func clearAdvisory() {
        advisory = nil
    }
}

// Tolerant decoding so blobs written by older app versions keep working as
// fields are added. The grid is authoritative when present and parseable; any
// failure (including slot kinds from a future version) falls back to the
// legacy fields, which every version keeps writing as a downgrade mirror.
extension UserConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case lunch, advisory, freePeriods, customizations,
             timeFormat, appearance, theme, periodPlans
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let customizations = try c.decodeIfPresent(
            [String: PeriodCustomization].self, forKey: .customizations) ?? [:]
        let timeFormat = try c.decodeIfPresent(TimeFormatPref.self, forKey: .timeFormat) ?? .system
        let appearance = try c.decodeIfPresent(AppearancePref.self, forKey: .appearance) ?? .system
        // A blob written before themes existed predates the Stevenson colours,
        // so it opts in like a fresh install rather than being pinned to Classic.
        let theme = try c.decodeIfPresent(ThemePref.self, forKey: .theme) ?? .stevenson

        if let raw = try? c.decodeIfPresent([String: PeriodPlan].self, forKey: .periodPlans) {
            // Keys are strings for JSON stability; merge (rather than trap) if
            // a corrupt blob aliases two spellings onto one period.
            let plans = Dictionary(
                raw.compactMap { key, value in Int(key).map { ($0, value) } },
                uniquingKeysWith: { first, _ in first })
            self.init(periodPlans: plans, customizations: customizations,
                      timeFormat: timeFormat, appearance: appearance, theme: theme)
        } else {
            self.init(
                lunch: try c.decodeIfPresent(SplitAssignment.self, forKey: .lunch),
                advisory: try c.decodeIfPresent(SplitAssignment.self, forKey: .advisory),
                freePeriods: try c.decodeIfPresent(Set<Int>.self, forKey: .freePeriods) ?? [],
                customizations: customizations,
                timeFormat: timeFormat, appearance: appearance, theme: theme)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let stringKeyed = Dictionary(uniqueKeysWithValues: periodPlans.map { (String($0.key), $0.value) })
        try c.encode(stringKeyed, forKey: .periodPlans)
        // Legacy mirrors so a downgraded build still reads a sensible config.
        try c.encodeIfPresent(lunch, forKey: .lunch)
        try c.encodeIfPresent(advisory, forKey: .advisory)
        try c.encode(freePeriods, forKey: .freePeriods)
        try c.encode(customizations, forKey: .customizations)
        try c.encode(timeFormat, forKey: .timeFormat)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(theme, forKey: .theme)
    }
}

/// A user-forced schedule type for one specific date. Keyed to the date, so it
/// expires naturally and a sync can never clobber it.
public enum OverrideType: Codable, Equatable, Hashable, Sendable {
    case bell(family: BellFamily, rotation: EDRotation?)
    case noSchool
    case asynchronous

    public var displayName: String {
        switch self {
        case .bell(let family, let rotation):
            if let rotation { return "\(family.displayName) · \(rotation.shortName)" }
            return family.displayName
        case .noSchool: return "No School"
        case .asynchronous: return "Asynchronous E-Learning"
        }
    }
}

public struct DayOverride: Codable, Equatable, Sendable {
    public var day: DayKey
    public var type: OverrideType

    public init(day: DayKey, type: OverrideType) {
        self.day = day
        self.type = type
    }
}
