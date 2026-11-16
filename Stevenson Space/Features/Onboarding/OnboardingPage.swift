import SwiftUI

/// Scrolling content over actions pinned where a thumb reaches them. At
/// accessibility text sizes the actions join the scroll instead, so they can't
/// crowd the content off a small screen.
struct OnboardingPage<Content: View, Actions: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// When this changes the page scrolls to its end, for a step whose
    /// answers add more content below them. The content itself must change
    /// without an animation: a scroll asked for while it is still growing
    /// does nothing.
    var revealing: AnyHashable?
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    private static var ground: Color { Color(.systemGroupedBackground) }
    private static var endID: String { "end" }

    var body: some View {
        ScrollViewReader { proxy in
            page
                .onChange(of: revealing) { _, _ in
                    withAnimation(.snappy(duration: 0.3)) {
                        proxy.scrollTo(Self.endID, anchor: .bottom)
                    }
                }
        }
    }

    private var page: some View {
        ScrollView {
            VStack(spacing: 24) {
                content
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) { actions }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .id(Self.endID)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Self.ground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { actions }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .background(Self.ground)
                    .overlay(alignment: .top) {
                        // Content fades out under the actions rather than
                        // being cut off at a hard edge.
                        LinearGradient(colors: [Self.ground.opacity(0), Self.ground],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 20)
                            .offset(y: -20)
                            .allowsHitTesting(false)
                    }
            }
        }
    }
}

/// The heading a setup step opens with.
struct OnboardingHeading: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The label over a group of controls inside a step.
struct OnboardingSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The app's full-width prominent button, as on the ID tab.
struct OnboardingPrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(StevensonPalette.accent)
    }
}

extension View {
    /// The rounded plate the app's cards sit on.
    func onboardingCard(cornerRadius: CGFloat = 18) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
    }
}
