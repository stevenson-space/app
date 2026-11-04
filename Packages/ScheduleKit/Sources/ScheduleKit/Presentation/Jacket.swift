import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The letter-jacket design system shared by the app and its widgets: the
/// school's green melton, gold leather, chenille lettering and twill edges.
/// The reasoning behind every value is in `docs/redesign/DIRECTION.md`.
public enum Jacket {
    // MARK: Grounds

    /// A block is on: class, lunch, advisory, free.
    public static let field = dynamic(light: 0x1D5A36, dark: 0x0E2F1D)
    /// Between bells: passing, switching halves, before the first bell.
    public static let gold = dynamic(light: 0xD3A33A, dark: 0x5C4413)
    /// No school right now, and every tab other than Home.
    public static let lining = dynamic(light: 0xEEF0EA, dark: 0x0B120E)
    /// Grouped rows and sheets on the lining.
    public static let raised = dynamic(light: 0xFFFFFF, dark: 0x152019)

    // MARK: Ink on the field
    //
    // Fixed in both appearances: Home draws its chrome dark over the green
    // field even in light mode, so these must not follow the trait.

    public static let chenille = Color(hex: 0xF3EAD2)
    /// Secondary text on the field; 4.8:1 on the light field, more on the dark.
    public static let chenille2 = Color(hex: 0xB9CDBB)
    /// The varsity number's gold edge and sewn progress. Material, not text.
    public static let twill = Color(hex: 0xC99A2C)
    /// The one live cue on the field: now and next-up.
    public static let goldInk = Color(hex: 0xE5C063)

    // MARK: Ink on the gold

    public static let goldText = dynamic(light: 0x13241A, dark: 0xF3EAD2)
    public static let goldText2 = dynamic(light: 0x3F3413, dark: 0xD8C9A3)
    /// The countdown's face on the gold side: green letters, chenille edge.
    public static let goldFace = dynamic(light: 0x1D5A36, dark: 0xF3EAD2)
    public static let goldEdge = dynamic(light: 0xF3EAD2, dark: 0xC99A2C)

    // MARK: Ink on the lining

    public static let ink = dynamic(light: 0x13241A, dark: 0xECEFE8)
    public static let ink2 = dynamic(light: 0x4D5E52, dark: 0xA3B0A6)
    /// Placeholders and glyphs only, never body text.
    public static let ink3 = dynamic(light: 0x7C8A80, dark: 0x6E7B72)
    /// Selection, today and the primary action. Also the system tint.
    public static let accent = dynamic(light: 0x1D6B3F, dark: 0x7CC293)
    public static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0B120E)
    /// Ink on a twill patch; at least 5:1 on both twill values.
    public static let patchInk = Color(hex: 0x13241A)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        Color(hex: light)
        #endif
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Grounds as a system

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

// MARK: - Type

public extension Font {
    /// SF Pro Expanded Heavy: the varsity number, for every numeral that
    /// identifies something and for screen titles.
    static func varsity(_ style: Font.TextStyle) -> Font {
        .system(style, weight: .heavy).width(.expanded)
    }

    static func varsity(size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.expanded)
    }

    /// 12pt Expanded Bold, set in caps by `jacketLabel()`.
    static let jacketLabel = Font.system(.caption, weight: .bold).width(.expanded)
}

public extension View {
    /// The tackle-twill edge: a hard offset copy in gold, no blur. Scale the
    /// offset with the type (3×4 at 96pt, 2×2.5 at 34pt).
    func twill(_ color: Color, x: CGFloat = 3, y: CGFloat = 4) -> some View {
        shadow(color: color, radius: 0, x: x, y: y)
    }

    /// Eyebrows and section labels.
    func jacketLabel() -> some View {
        font(.jacketLabel)
            .textCase(.uppercase)
            .tracking(1.2)
    }
}

// MARK: - Stitches

/// A running stitch: the rule between rows and sections.
public struct StitchRule: View {
    private let color: Color

    public init(_ color: Color) {
        self.color = color
    }

    public var body: some View {
        StitchLine()
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3.5]))
            .frame(height: 1.5)
            .accessibilityHidden(true)
    }
}

private struct StitchLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Progress as a seam: stitches turn gold as the block elapses. Decorative;
/// the countdown beside it carries the value for VoiceOver.
public struct Seam: View {
    private let fraction: Double
    private let on: Color
    private let off: Color
    private let stitches: Int
    private let height: CGFloat
    private let spacing: CGFloat

    public init(fraction: Double, on: Color, off: Color,
                stitches: Int = 30, height: CGFloat = 4, spacing: CGFloat = 3) {
        self.fraction = min(max(fraction, 0), 1)
        self.on = on
        self.off = off
        self.stitches = stitches
        self.height = height
        self.spacing = spacing
    }

    public var body: some View {
        let sewn = Int((fraction * Double(stitches)).rounded(.down))
        HStack(spacing: spacing) {
            ForEach(0..<stitches, id: \.self) { index in
                Capsule().fill(index < sewn ? on : off)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A sewn-on patch: how a special day announces itself.
public struct JacketPatch: View {
    private let title: String
    private let systemImage: String

    public init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        Label(title, systemImage: systemImage)
            .jacketLabel()
            .tracking(0.6)
            .foregroundStyle(Jacket.patchInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 32)
            .background {
                Capsule().fill(Jacket.twill)
                Capsule()
                    .inset(by: 3)
                    .stroke(Jacket.patchInk.opacity(0.42),
                            style: StrokeStyle(lineWidth: 1.2, dash: [3.5, 3]))
            }
    }
}
