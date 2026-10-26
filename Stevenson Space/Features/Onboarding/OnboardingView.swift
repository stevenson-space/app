import SwiftUI
import ScheduleKit

/// Where the tour is. Each page reads it to know whether its demo should run.
@Observable
final class OnboardingFlow {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome, countdown, specialDays, lunch, studentID, widgets, siri,
             classes, notifications, finish

        var id: Self { self }
    }

    /// The steps the progress bar counts: everything between the green pages.
    static let progressSteps = Step.allCases.filter { $0 != .welcome && $0 != .finish }

    var step: Step = .welcome
    var isEditingClasses = false
    let finish: () -> Void

    init(finish: @escaping () -> Void) {
        self.finish = finish
    }

    var isTour: Bool { (Step.countdown...Step.siri).contains(step) }

    func advance() { step = Step(rawValue: step.rawValue + 1) ?? .finish }
    func back() { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
    /// Skipping the tour still offers the two setup steps.
    func skipTour() { step = .classes }
}

extension OnboardingFlow.Step: Comparable {
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The first-launch tour: what the app does, shown with working demos, then
/// two optional setup steps. Settings › Welcome Tour replays it.
struct OnboardingView: View {
    @State private var flow: OnboardingFlow
    /// The page scrolled to. Kept apart from `flow.step` because the scroll
    /// view writes it mid-update, when a change to `flow` can go unseen;
    /// `onChange` passes it on afterward.
    @State private var position: OnboardingFlow.Step? = .welcome

    init(finish: @escaping () -> Void) {
        _flow = State(initialValue: OnboardingFlow(finish: finish))
    }

    var body: some View {
        @Bindable var flow = flow
        NavigationStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(OnboardingFlow.Step.allCases) { step in
                        page(step)
                            .containerRelativeFrame(.horizontal)
                            .accessibilityHidden(step != flow.step)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position)
            .onChange(of: position) { _, position in
                if let position, position != flow.step { flow.step = position }
            }
            .onChange(of: flow.step) { _, step in
                guard position != step else { return }
                withAnimation(.smooth(duration: 0.45)) { position = step }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .top, spacing: 0) {
                OnboardingTopBar()
            }
            .navigationTitle("Tour")
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $flow.isEditingClasses) {
                PeriodEditorListView()
            }
        }
        .environment(flow)
        .sensoryFeedback(trigger: flow.step) { _, step in
            step == .finish ? .success : .impact(weight: .light)
        }
    }

    @ViewBuilder
    private func page(_ step: OnboardingFlow.Step) -> some View {
        switch step {
        case .welcome: OnboardingWelcomePage()
        case .countdown: OnboardingCountdownPage()
        case .specialDays: OnboardingSpecialDaysPage()
        case .lunch: OnboardingLunchPage()
        case .studentID: OnboardingStudentIDPage()
        case .widgets: OnboardingWidgetsPage()
        case .siri: OnboardingSiriPage()
        case .classes: OnboardingClassesPage()
        case .notifications: OnboardingNotificationsPage()
        case .finish: OnboardingFinishPage()
        }
    }
}

// MARK: - Top bar

/// Back, the day-so-far progress bar, and Skip. Hidden on the two green pages
/// but always laid out, so pages don't jump as they slide past.
private struct OnboardingTopBar: View {
    @Environment(OnboardingFlow.self) private var flow

    private var isShown: Bool { flow.step != .welcome && flow.step != .finish }

    var body: some View {
        HStack(spacing: 8) {
            Button("Back", systemImage: "chevron.left", action: flow.back)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

            OnboardingProgressBar(step: flow.step)

            Button("Skip", action: flow.skipTour)
                .font(.body.weight(.medium))
                .frame(minWidth: 44, minHeight: 44)
                .opacity(flow.isTour ? 1 : 0)
                .disabled(!flow.isTour)
                .accessibilityHidden(!flow.isTour)
                .accessibilityHint("Skips to setting up your classes")
        }
        .tint(StevensonPalette.accent)
        .padding(.horizontal, 8)
        // Leave room for the progress bar between Back and Skip.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .opacity(isShown ? 1 : 0)
        .disabled(!isShown)
        .accessibilityHidden(!isShown)
        .animation(.smooth(duration: 0.25), value: isShown)
    }
}

/// One segment per step, filling left to right like a day of periods.
private struct OnboardingProgressBar: View {
    let step: OnboardingFlow.Step

    var body: some View {
        let steps = OnboardingFlow.progressSteps
        let current = steps.firstIndex(of: step) ?? (step == .finish ? steps.count : -1)
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, _ in
                Capsule()
                    .fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(StevensonPalette.accent)
                            .scaleEffect(x: index <= current ? 1 : 0, anchor: .leading)
                    }
                    .frame(height: 5)
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tour progress")
        .accessibilityValue("Step \(max(current + 1, 1)) of \(steps.count)")
    }
}

// MARK: - Page layout

/// A tour page: a live demo on top, the words under it, actions pinned to the
/// bottom. `brand` pages are the green welcome and finish screens.
struct OnboardingPage<Stage: View, Content: View, Actions: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewportHeight: CGFloat = 0
    @State private var stageHeight: CGFloat = 0
    var brand = false
    /// How much of the screen the demo claims before the words start.
    var stageShare: CGFloat = 0.5
    @ViewBuilder let stage: Stage
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    /// A demo taller than this shrinks to fit, so the words stay in view on
    /// small phones and at large text sizes.
    private var stageLimit: CGFloat {
        max(viewportHeight * (dynamicTypeSize.isAccessibilitySize ? 0.42 : 0.62), 200)
    }

    var body: some View {
        let scale = stageHeight > 0 ? min(1, stageLimit / stageHeight) : 1
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                stage
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        stageHeight = height
                    }
                    .scaleEffect(scale, anchor: .top)
                    .frame(height: stageHeight > 0 ? stageHeight * scale : nil, alignment: .top)
                    .frame(maxWidth: .infinity, minHeight: min(max(viewportHeight * stageShare, 240), 440))
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { geometry in
            // The scroll view sits inside the safe area, so this is already
            // the space between the top bar and the buttons.
            geometry.size.height
        } action: { height in
            viewportHeight = height
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                actions
            }
            .buttonStyle(OnboardingButtonStyle(brand: brand))
            .frame(maxWidth: 480)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(ground.ignoresSafeArea())
        }
        .background(ground.ignoresSafeArea())
        // White type and controls on the green pages, whatever the appearance.
        .environment(\.colorScheme, brand ? .dark : colorScheme)
    }

    private var ground: Color {
        brand ? StevensonPalette.green : Color(.systemGroupedBackground)
    }
}

/// The words on a page: where the feature lives, what it is, how it helps.
struct OnboardingHeadline: View {
    var eyebrow: LocalizedStringKey?
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StevensonPalette.accent)
            }
            Text(title)
                .font(.largeTitle.bold())
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Change it later" lines, so skipping never feels permanent.
struct OnboardingFootnote: View {
    let text: LocalizedStringKey
    var systemImage = "gearshape"

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Filled capsule for the main action, plain text for the alternative. Put
/// `.onboardingSecondary()` on a button to get the second look.
struct OnboardingButtonStyle: ButtonStyle {
    let brand: Bool

    func makeBody(configuration: Configuration) -> some View {
        OnboardingButton(configuration: configuration, brand: brand)
    }

    private struct OnboardingButton: View {
        let configuration: Configuration
        let brand: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.onboardingSecondaryButton) private var isSecondary

        private var fill: Color { brand ? StevensonPalette.gold : StevensonPalette.accent }

        var body: some View {
            configuration.label
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, isSecondary ? 10 : 15)
                .frame(maxWidth: .infinity, minHeight: isSecondary ? 44 : 54)
                .foregroundStyle(isSecondary
                                 ? AnyShapeStyle(brand ? Color.white : StevensonPalette.accent)
                                 : AnyShapeStyle(.contrasting(on: fill)))
                .background {
                    if !isSecondary {
                        Capsule().fill(fill)
                    }
                }
                .contentShape(Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }
}

extension EnvironmentValues {
    @Entry var onboardingSecondaryButton = false
}

extension View {
    func onboardingSecondary() -> some View {
        environment(\.onboardingSecondaryButton, true)
    }
}
