import SwiftUI

/// What the screen is made of right now. Each ground carries its own inks, so
/// views ask the ground rather than choosing colours themselves.
public enum JacketGround: Hashable, Sendable {
    case field, gold, lining

    /// Green while a block is on, gold between bells, the plain lining when
    /// there is no school right now.
    public init(state: MomentState) {
        switch state {
        case .inBlock: self = .field
        case .passing, .beforeSchool: self = .gold
        default: self = .lining
        }
    }

    public var background: Color {
        switch self {
        case .field: Jacket.field
        case .gold: Jacket.gold
        case .lining: Jacket.lining
        }
    }

    public var ink: Color {
        switch self {
        case .field: Jacket.chenille
        case .gold: Jacket.goldText
        case .lining: Jacket.ink
        }
    }

    public var ink2: Color {
        switch self {
        case .field: Jacket.chenille2
        case .gold: Jacket.goldText2
        case .lining: Jacket.ink2
        }
    }

    /// The one live cue: the eyebrow, Now, next-up.
    public var live: Color {
        switch self {
        case .field: Jacket.goldInk
        case .gold: Jacket.goldText2
        case .lining: Jacket.accent
        }
    }

    public var heroFace: Color {
        switch self {
        case .field: Jacket.chenille
        case .gold: Jacket.goldFace
        case .lining: Jacket.accent
        }
    }

    public var heroEdge: Color {
        switch self {
        case .field, .lining: Jacket.twill
        case .gold: Jacket.goldEdge
        }
    }

    /// Running stitches between rows.
    public var stitch: Color {
        switch self {
        case .field: Jacket.chenille.opacity(0.17)
        case .gold: Jacket.goldText.opacity(0.2)
        case .lining: Jacket.ink.opacity(0.16)
        }
    }

    public var seamOn: Color {
        switch self {
        case .field, .lining: Jacket.twill
        case .gold: Jacket.goldFace
        }
    }

    public var seamOff: Color {
        switch self {
        case .field: Jacket.chenille.opacity(0.24)
        case .gold: Jacket.goldText.opacity(0.18)
        case .lining: Jacket.ink.opacity(0.14)
        }
    }

    /// Whether bars over this ground need light content (white status bar).
    public func isDark(in scheme: ColorScheme) -> Bool {
        self == .field || scheme == .dark
    }
}

public extension EnvironmentValues {
    /// The ground a view sits on, so shared rows and reminders pick its inks.
    @Entry var jacketGround: JacketGround = .lining
}
