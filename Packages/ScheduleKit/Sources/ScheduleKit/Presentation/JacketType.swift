import SwiftUI

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
