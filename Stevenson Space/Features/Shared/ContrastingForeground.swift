import SwiftUI

/// Black or white, whichever contrasts more with `fill` as it resolves in the
/// current environment.
///
/// System tints get lighter in Dark Mode and lighter again with Increase
/// Contrast, so a fixed white label on a tinted fill can drop far below the
/// 4.5:1 that text needs (white on teal reaches 1.6:1). Black and white tie at
/// a relative luminance of about 0.18, where each gives 4.58:1, so the label
/// never does worse than that.
struct ContrastingForeground: ShapeStyle {
    let fill: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        let color = fill.resolve(in: environment)
        let luminance = 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        return luminance > 0.179 ? .black : .white
    }
}

extension ShapeStyle where Self == ContrastingForeground {
    static func contrasting(on fill: Color) -> ContrastingForeground {
        ContrastingForeground(fill: fill)
    }
}
