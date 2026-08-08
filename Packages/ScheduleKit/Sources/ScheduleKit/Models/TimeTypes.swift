import Foundation

/// A wall-clock time of day in the school's timezone. Bell times are stored as
/// components and materialized per calendar day, so DST cannot shift them.
public struct HourMinute: Hashable, Codable, Comparable, Sendable {
    // Immutable validated storage: bounds are enforced once at construction and
    // can't be bypassed by later mutation (hour 24 → 23, etc.).
    public private(set) var hour: Int
    public private(set) var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Parses "8:30" or "15:25" (24-hour).
    public init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.init(hour: hour, minute: minute)
    }

    private enum CodingKeys: String, CodingKey { case hour, minute }

    /// Route decoding through the validating initializer so a stored blob can't
    /// resurrect an out-of-range time.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hour: try c.decode(Int.self, forKey: .hour),
                  minute: try c.decode(Int.self, forKey: .minute))
    }

    public var totalMinutes: Int { hour * 60 + minute }

    public static func < (lhs: HourMinute, rhs: HourMinute) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

/// One half of an A/B period subdivision.
public enum Half: String, Codable, Hashable, Sendable {
    case a = "A"
    case b = "B"
}

/// A student's lunch/advisory placement within a period.
public enum HalfChoice: String, Codable, Hashable, CaseIterable, Sendable {
    case a = "A"
    case b = "B"
    case full = "full"

    public var displayName: String {
        switch self {
        case .a: return "A (first half)"
        case .b: return "B (second half)"
        case .full: return "Full period"
        }
    }
}
