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
            .background {
                theme.heroBackground
                    // The status bar sits on a lighter green so the black clock
                    // stays legible; this eases that back down to the band over
                    // the empty space beneath it, so the two read as one field
                    // rather than two stacked greens. Classic blends clear into
                    // clear and nothing is drawn.
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [theme.statusField,
                                                theme.heroBackground],
                                       startPoint: .top, endPoint: .bottom)
                        .frame(height: 36)
                    }
            }
            .clipShape(
                UnevenRoundedRectangle(bottomLeadingRadius: 32,
                                       bottomTrailingRadius: 32,
                                       style: .continuous)
            )
    }
}

/// Paints `fill` across the top safe-area inset, so a coloured header reads as
/// one field running under the clock rather than a band with a grey lid.
///
/// It has to be an overlay rather than a background: a `ScrollView`'s frame
/// already spans the inset, so its own background covers anything layered
/// behind it. The `GeometryReader` is only there to measure the inset — the
/// strip is exactly that tall, and never touches the content below it.
private struct StatusBarField: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GeometryReader { proxy in
                fill
                    .frame(height: proxy.safeAreaInsets.top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Extends `fill` up through the status bar. `Color.clear` — what Classic
    /// resolves to — leaves the screen exactly as it was.
    func statusBarField(_ fill: Color) -> some View {
        modifier(StatusBarField(fill: fill))
    }
}
