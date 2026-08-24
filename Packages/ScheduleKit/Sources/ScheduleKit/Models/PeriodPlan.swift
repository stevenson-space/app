import Foundation

/// What one half of a numbered period holds in the student's week.
public enum HalfSlotAssignment: Equatable, Hashable, Sendable {
    /// Part of the class anchored at `anchor` — the period fully contained in
    /// the class, which also keys its name/room customization. A normal class
    /// anchors at its own period; a 1½-period class additionally claims an
    /// adjacent half whose slot points back at the anchor (chemistry 2–3A ⇒
    /// period 3's A half is `.classSlot(anchor: 2)`).
    case classSlot(anchor: Int)
    case lunch
    case advisory
    case free

    public var classAnchor: Int? {
        if case .classSlot(let anchor) = self { return anchor }
        return nil
    }
}

// Encoded as a single string ("lunch", "class:4") so stored plans stay small
// and greppable. Unknown kinds throw: UserConfig catches the failure and falls
// back to the legacy lunch/advisory/free fields every version keeps writing.
extension HalfSlotAssignment: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "lunch": self = .lunch
        case "advisory": self = .advisory
        case "free": self = .free
        default:
            guard raw.hasPrefix("class:"), let anchor = Int(raw.dropFirst("class:".count)) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown half-slot assignment '\(raw)'"))
            }
            self = .classSlot(anchor: anchor)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .lunch: try container.encode("lunch")
        case .advisory: try container.encode("advisory")
        case .free: try container.encode("free")
        case .classSlot(let anchor): try container.encode("class:\(anchor)")
        }
    }
}

/// How long a class runs relative to its anchor period.
public enum ClassLength: Equatable, Hashable, Sendable {
    /// One full period.
    case standard
    /// 1½ periods: the anchor period plus the next period's A half.
    case extendsForward
    /// 1½ periods: the previous period's B half plus the anchor period.
    case startsEarly
}

/// A student's plan for one numbered period: what each half holds. A period
/// with no stored plan defaults to `standardClass` — a full-period class
/// anchored at the period itself.
public struct PeriodPlan: Equatable, Hashable, Codable, Sendable {
    public var a: HalfSlotAssignment
    public var b: HalfSlotAssignment

    public init(a: HalfSlotAssignment, b: HalfSlotAssignment) {
        self.a = a
        self.b = b
    }

    public static func standardClass(_ n: Int) -> PeriodPlan {
        PeriodPlan(a: .classSlot(anchor: n), b: .classSlot(anchor: n))
    }

    public var isUniform: Bool { a == b }

    public func isStandardClass(for n: Int) -> Bool { self == .standardClass(n) }

    public func slot(_ half: Half) -> HalfSlotAssignment {
        half == .a ? a : b
    }

    public mutating func setSlot(_ half: Half, _ new: HalfSlotAssignment) {
        if half == .a { a = new } else { b = new }
    }
}
