import Foundation

/// Stable identity of a block on the bell schedule. Customizations, rotations,
/// and notifications key on this — never on a block's position in the day,
/// because Early Dismissal runs periods out of order.
public enum PeriodID: Hashable, Sendable {
    case period(Int) // 1...8
    case homeroom
    case activity
    case assembly
    case makeup
    case summer
}

extension PeriodID {
    /// Stable string used for persistence keys and JSON.
    public var storageKey: String {
        switch self {
        case .period(let n): return String(n)
        case .homeroom: return "homeroom"
        case .activity: return "activity"
        case .assembly: return "assembly"
        case .makeup: return "makeup"
        case .summer: return "summer"
        }
    }

    public init?(storageKey: String) {
        switch storageKey {
        case "homeroom": self = .homeroom
        case "activity": self = .activity
        case "assembly": self = .assembly
        case "makeup": self = .makeup
        case "summer": self = .summer
        default:
            guard let n = Int(storageKey), (1...8).contains(n) else { return nil }
            self = .period(n)
        }
    }

    public var periodNumber: Int? {
        if case .period(let n) = self { return n }
        return nil
    }

    /// Display name before any user customization.
    public var defaultDisplayName: String {
        switch self {
        case .period(let n): return "\(Self.ordinal(n)) Period"
        case .homeroom: return "Homeroom"
        case .activity: return "Activity"
        case .assembly: return "Assembly"
        case .makeup: return "Makeup"
        case .summer: return "Summer School"
        }
    }

    public static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }
}

extension PeriodID: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let id = PeriodID(storageKey: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown period id '\(raw)'"))
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageKey)
    }
}
