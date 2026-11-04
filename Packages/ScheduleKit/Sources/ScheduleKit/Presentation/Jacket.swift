import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
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
        #elseif canImport(AppKit)
        // So the host-side test suite can check both appearances.
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
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
