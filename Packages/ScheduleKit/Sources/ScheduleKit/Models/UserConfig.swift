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

public struct PeriodCustomization: Codable, Equatable, Sendable {
    public var name: String?
    public var room: String?

    public init(name: String? = nil, room: String? = nil) {
        self.name = name
        self.room = room
    }

    public var isEmpty: Bool {
        (name?.isEmpty ?? true) && (room?.isEmpty ?? true)
    }
}

/// Where the student's lunch (or advisory) sits: which numbered period, and
/// whether it occupies the A half, B half, or the full period. On days whose
/// schedule has no A/B subdivisions, an A/B choice falls back to the full period.
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
    public var lunch: SplitAssignment?
    public var advisory: SplitAssignment?
    /// Numbered periods (1–8) the student doesn't attend.
    public var freePeriods: Set<Int>
    /// Keyed by `PeriodID.storageKey` — identity, never position.
    public var customizations: [String: PeriodCustomization]
    public var hideFreePeriods: Bool
    public var timeFormat: TimeFormatPref

    public init(lunch: SplitAssignment? = nil,
                advisory: SplitAssignment? = nil,
                freePeriods: Set<Int> = [],
                customizations: [String: PeriodCustomization] = [:],
                hideFreePeriods: Bool = false,
                timeFormat: TimeFormatPref = .system) {
        self.lunch = lunch
        self.advisory = advisory
        self.freePeriods = freePeriods
        self.customizations = customizations
        self.hideFreePeriods = hideFreePeriods
        self.timeFormat = timeFormat
    }

    public func customization(for id: PeriodID) -> PeriodCustomization? {
        customizations[id.storageKey]
    }
}

extension UserConfig {
    /// Advisory (freshmen only) is never placed independently: it occupies one
    /// half of one of the lunch periods (4–6), and lunch automatically takes
    /// the other half of the same period. Advisory 4A ⇒ lunch 4B, advisory
    /// 5B ⇒ lunch 5A, and so on. This is the only way advisory gets set.
    public var hasAdvisory: Bool { advisory != nil }

    public mutating func setPairedAdvisory(basePeriod: Int, advisoryHalf: Half) {
        // Advisory/lunch only live in periods 4–6; ignore out-of-range requests
        // rather than persisting an impossible placement.
        guard (4...6).contains(basePeriod) else { return }
        let advisoryChoice: HalfChoice = advisoryHalf == .a ? .a : .b
        let lunchChoice: HalfChoice = advisoryHalf == .a ? .b : .a
        advisory = SplitAssignment(basePeriod: basePeriod, choice: advisoryChoice)
        lunch = SplitAssignment(basePeriod: basePeriod, choice: lunchChoice)
    }

    /// Turning advisory off keeps the derived lunch half as a plain lunch
    /// selection — the student still eats at the same time.
    public mutating func clearAdvisory() {
        advisory = nil
    }
}

// Tolerant decoding so blobs written by older app versions keep working as
// fields are added.
extension UserConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case lunch, advisory, freePeriods, customizations, hideFreePeriods, timeFormat
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lunch = try c.decodeIfPresent(SplitAssignment.self, forKey: .lunch)
        advisory = try c.decodeIfPresent(SplitAssignment.self, forKey: .advisory)
        freePeriods = try c.decodeIfPresent(Set<Int>.self, forKey: .freePeriods) ?? []
        customizations = try c.decodeIfPresent([String: PeriodCustomization].self, forKey: .customizations) ?? [:]
        hideFreePeriods = try c.decodeIfPresent(Bool.self, forKey: .hideFreePeriods) ?? false
        timeFormat = try c.decodeIfPresent(TimeFormatPref.self, forKey: .timeFormat) ?? .system
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
