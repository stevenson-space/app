import SwiftUI

/// First-run onboarding: one screen that shows the countdown working, then
/// three short steps a student can skip. A plain navigation stack, so Back and
/// the edge swipe behave as they do everywhere else in the app.
struct OnboardingView: View {
    @Environment(SceneNavigation.self) private var navigation
    @State private var path: [Step] = []

    enum Step: Hashable {
        case lunch, classes, extras
    }

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingWelcomeView(
                start: { path.append(.lunch) },
                skip: { navigation.finishOnboarding() })
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .lunch:
                        OnboardingLunchView { path.append(.classes) }
                    case .classes:
                        OnboardingClassesView { path.append(.extras) }
                    case .extras:
                        OnboardingExtrasView { navigation.finishOnboarding(opening: $0) }
                    }
                }
        }
        .tint(StevensonPalette.accent)
    }
}
