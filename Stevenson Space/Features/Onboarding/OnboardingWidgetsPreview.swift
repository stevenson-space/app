import SwiftUI

/// A picture of the real School Schedule widget, captured from the Home
/// Screen, over the steps to add it. Widgets are added from the Home Screen and
/// Lock Screen, not from here, so the steps fold away until asked for.
struct OnboardingWidgetsPreview: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsSteps = false

    private static let stepsID = "widgetSteps"

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 8) {
                OnboardingSectionLabel("Widgets")

                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.snappy(duration: 0.35)) {
                            showsSteps.toggle()
                            if showsSteps {
                                // Opened at the bottom of the page, the steps
                                // would otherwise start below the screen.
                                proxy.scrollTo(Self.stepsID, anchor: .bottom)
                            }
                        }
                    } label: {
                        summary
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showsSteps ? "Steps shown" : "Steps hidden")
                    .accessibilityHint(showsSteps ? "Hides the steps." : "Shows how to add the widget.")

                    if showsSteps {
                        VStack(alignment: .leading, spacing: 18) {
                            Divider()
                            StepList(title: "Home Screen", steps: [
                                "Touch and hold an empty spot until the apps jiggle.",
                                "Tap Edit, then Add Widget.",
                                "Search for SHS Space.",
                                "Pick a size and tap Add Widget.",
                            ])
                            StepList(title: "Lock Screen", steps: [
                                "Touch and hold the Lock Screen, then tap Customize.",
                                "Tap Lock Screen.",
                                "Tap the space under the time.",
                                "Pick SHS Space, then a widget.",
                            ])
                        }
                        .padding(.top, 16)
                        .transition(.opacity)
                    }
                }
                .padding(16)
                .onboardingCard(cornerRadius: 16)
                .id(Self.stepsID)
            }
        }
    }

    /// The widget and what it does, with the control that opens the steps.
    private var summary: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        return layout {
            Image("WidgetPreview")
                .resizable()
                .scaledToFit()
                .frame(width: 116)
                // The image's corners are cut with this radius, so the edge
                // stays visible on the card in dark mode.
                .overlay(RoundedRectangle(cornerRadius: 19)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .accessibilityLabel("The School Schedule widget, counting down to the end of 3rd Period")

            VStack(alignment: .leading, spacing: 10) {
                Text("Keep the countdown on your Home Screen and Lock Screen.")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    Text(showsSteps ? "Hide steps" : "Show me how")
                    Image(systemName: "chevron.down")
                        .imageScale(.small)
                        .rotationEffect(.degrees(showsSteps ? 180 : 0))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(StevensonPalette.accent)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

/// Numbered steps under a heading.
private struct StepList: View {
    let title: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(StevensonPalette.accent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(StevensonPalette.accent.opacity(0.15)))
                        // Sit the badge's number on the step's first line.
                        .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] }
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
