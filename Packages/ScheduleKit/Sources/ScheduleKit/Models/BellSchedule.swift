import Foundation

/// One timed block in a bell table (times are wall-clock; interval is half-open
/// [start, end) when materialized).
public struct Block: Hashable, Codable, Sendable {
    public var id: PeriodID
    public var half: Half?
    public var start: HourMinute
    public var end: HourMinute

    public init(id: PeriodID, half: Half? = nil, start: HourMinute, end: HourMinute) {
        self.id = id
        self.half = half
        self.start = start
        self.end = end
    }
}

/// The family a bell table belongs to. Remote-map keys resolve to a family;
/// Early Dismissal additionally needs a rotation to pick a concrete table.
public enum BellFamily: String, Codable, CaseIterable, Hashable, Sendable {
    case standard
    case lateArrival
    case odyssey
    case activityPeriod
    case pmAssembly
    case earlyDismissal
    case summer

    public var displayName: String {
        switch self {
        case .standard: return "Standard Schedule"
        case .lateArrival: return "Late Arrival"
        case .odyssey: return "Odyssey"
        case .activityPeriod: return "Activity Period"
        case .pmAssembly: return "PM Assembly"
        case .earlyDismissal: return "Early Dismissal"
        case .summer: return "Summer School"
        }
    }
}

/// Finals-day rotation for Early Dismissal.
public enum EDRotation: Int, Codable, Hashable, CaseIterable, Sendable {
    case rotation1 = 1
    case rotation2 = 2

    public var displayName: String {
        switch self {
        case .rotation1: return "Finals Day 1 · Periods 6, 2, 3, 4"
        case .rotation2: return "Finals Day 2 · Periods 5, 1, 7, 8"
        }
    }

    public var shortName: String {
        switch self {
        case .rotation1: return "Finals Day 1"
        case .rotation2: return "Finals Day 2"
        }
    }
}

/// A complete bundled bell table for one schedule type (and rotation, for ED).
public struct BellSchedule: Hashable, Sendable {
    public let id: String
    public let family: BellFamily
    public let rotation: EDRotation?
    public let displayName: String
    /// The day's spine, in the order the day runs.
    public let fullBlocks: [Block]
    /// A/B subdivision rows (only Standard, Activity Period, PM Assembly).
    /// Used solely to render the user's lunch/advisory period.
    public let abBlocks: [Block]

    public var hasABVariants: Bool { !abBlocks.isEmpty }

    /// The A and B rows for a numbered period, in half order.
    public func abBlocks(forPeriod number: Int) -> [Block] {
        abBlocks
            .filter { $0.id == .period(number) }
            .sorted { ($0.half == .a ? 0 : 1) < ($1.half == .a ? 0 : 1) }
    }
}
