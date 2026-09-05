import SwiftUI

/// The colour block at the top of Home: the school-green field the day header
/// and the countdown sit in, curved off at the bottom where the day's cards
/// begin. Full-bleed horizontally, so it reads as the screen's header rather
/// than another card.
///
/// Under Classic the fill is `clear` and this is pure layout — the surface
/// stays exactly as it shipped.
struct HeroBand<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, theme.hasHeroBand ? 16 : 12)
            .padding(.bottom, theme.hasHeroBand ? 28 : 0)
            .background(theme.heroBackground)
            .clipShape(
                UnevenRoundedRectangle(bottomLeadingRadius: 32,
                                       bottomTrailingRadius: 32,
                                       style: .continuous)
            )
    }
}
