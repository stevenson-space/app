import SwiftUI

/// Scrolling content over actions pinned where a thumb reaches them. At
/// accessibility text sizes the actions join the scroll instead, so they can't
/// crowd the content off a small screen.
struct OnboardingPage<Content: View, Actions: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The `id` of the part of the content just answered, for a step whose
    /// answers add more content below them. When it changes the page brings
    /// that part to the top, so what it added follows it on screen whatever
    /// the screen's height. The content itself must change without an
    /// animation: a scroll asked for while it is still growing does nothing.
    var revealing: AnyHashable?
    /// Whether a field on the page is being typed in: the only time the page
    /// makes room for the keyboard. A step that the next one covers can be
    /// left holding room for a keyboard that isn't there (turn an iPad while
    /// it is covered, any time after something was typed), and would come
    /// back with its actions in the middle of the screen.
    var isTyping = false
    /// Puts content shorter than the screen in the middle of the room above
    /// the actions. For a page with no heading to hold its top: left at the
    /// top, the welcome sits over a third of an iPad's screen of nothing.
    var centersContent = false
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    /// The height the scroll view shows between the bars and the actions.
    @State private var roomForContent: CGFloat = 0

    private static var ground: Color { Color(.systemGroupedBackground) }
    private static var fadeHeight: CGFloat { 20 }

    var body: some View {
        ScrollViewReader { proxy in
            page
                .ignoresSafeArea(isTyping ? [] : .keyboard, edges: .bottom)
                .onChange(of: revealing) { _, answered in
                    guard let answered else { return }
                    withAnimation(.snappy(duration: 0.3)) {
                        proxy.scrollTo(answered, anchor: .top)
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
            // The pinned actions bring their own fade, which stands in for
            // most of the space under the last of the content.
            .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 24 : 24 - Self.fadeHeight)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, minHeight: centersContent ? roomForContent : nil)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // The visible rect runs under the bars and the actions; the insets
            // are how far.
            let insets = geometry.contentInsets
            return max(geometry.visibleRect.height - insets.top - insets.bottom, 0)
        } action: { _, room in
            roomForContent = room
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Self.ground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    // Content fades out under the actions rather than being
                    // cut off at a hard edge. The fade is part of the inset,
                    // so a field being typed in is kept clear of it.
                    LinearGradient(colors: [Self.ground.opacity(0), Self.ground],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.fadeHeight)
                        .allowsHitTesting(false)

                    VStack(spacing: 8) { actions }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                        .background(Self.ground)
                }
            }
        }
    }
}

/// The heading a setup step opens with.
struct OnboardingHeading: View {
    let title: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
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
