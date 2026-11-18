import SwiftUI

/// A picture of the real School Schedule widget, captured from the Home
/// Screen, with where to add it. Widgets are added from the Home Screen and
/// Lock Screen, not from here, so the text says how.
struct OnboardingWidgetsPreview: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 8) {
            OnboardingSectionLabel("Widgets")

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                Image("WidgetPreview")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 116)
                    // The image's corners are cut with this radius, so the
                    // edge stays visible on the card in dark mode.
                    .overlay(RoundedRectangle(cornerRadius: 19)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .accessibilityLabel("The School Schedule widget, counting down to the end of 3rd Period")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Keep the countdown on your Home Screen.")
                        .font(.subheadline.weight(.semibold))
                    Text("Touch and hold an empty spot on your Home Screen, tap Edit, then Add Widget and search for SHS Space. For the Lock Screen, touch and hold it and tap Customize.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .onboardingCard(cornerRadius: 16)
        }
    }
}
