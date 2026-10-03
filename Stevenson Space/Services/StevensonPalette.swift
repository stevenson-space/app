import SwiftUI

/// Stevenson's colours, sampled from the Patriot crest the app icon already
/// ships, so the ID card matches the real crest rather than an approximation.
enum StevensonPalette {
    /// #1F5D39 — the crest's green. Carries white text at about 7.9:1.
    static let green = Color(red: 0.122, green: 0.365, blue: 0.224)
    /// #C99A2C — the crest's gold. Carries black text at about 8.2:1.
    static let gold = Color(red: 0.788, green: 0.604, blue: 0.173)
    /// A half-stop down from `gold`, for the printed-stock gradient.
    static let goldShade = Color(red: 0.710, green: 0.529, blue: 0.129)
    /// Card ink. Not `.primary`: the card keeps its printed colours in both
    /// appearances, so its text must not invert with the system.
    static let cardInk = Color(red: 0.086, green: 0.086, blue: 0.098)

    /// The interactive green used for selection and controls, which does have to
    /// adapt: the light value is dark enough to carry white text, the dark value
    /// light enough to read against a dark background.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.24, green: 0.59, blue: 0.33, alpha: 1)
            : UIColor(red: 0.09, green: 0.48, blue: 0.21, alpha: 1)
    })
}
