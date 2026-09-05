import SwiftUI

/// The ID card's colours, sampled from the Patriot crest the app icon already
/// ships, so the card matches the real crest rather than an approximation.
///
/// Deliberately *not* `StevensonBrand`, which is what the app's chrome wears.
/// The card emulates printed stock: it keeps crest fidelity, doesn't follow
/// dark mode, and its gold is a lighter, more legible print gold (ink reads at
/// 7.0:1 here versus 5.6:1 on the brand gold). The two greens are within a
/// couple of percent of each other and read as the same school green.
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
}
