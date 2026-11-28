import SwiftUI
import ScheduleKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation: SceneNavigation

    init(model: AppModel) {
        _navigation = State(initialValue: SceneNavigation(model: model))
    }

    var body: some View {
        @Bindable var navigation = navigation
        ZStack {
            // One or the other, never both: the tabs stay out of the way of
            // VoiceOver and the keyboard until onboarding is done.
            if navigation.isAwaitingOnboardingDecision {
                // The launch screen's colour, held until it is known which.
                Color(.systemBackground)
                    .ignoresSafeArea()
            } else if navigation.isOnboardingPresented {
                OnboardingView()
                    .transition(.opacity)
            } else {
                TabView(selection: Binding(
                    get: { navigation.selectedTab },
                    set: { tab in
                        // Tapping Home while it's showing takes it back to today.
                        if tab == .home, navigation.selectedTab == .home {
                            navigation.returnHomeToToday()
                        }
                        navigation.selectedTab = tab
                    })) {
                    Tab(value: RootTab.home) {
                        HomeView()
                    } label: {
                        TabLabel("Home", systemImage: "clock")
                    }
                    Tab(value: RootTab.lunch) {
                        LunchMenuView()
                    } label: {
                        TabLabel("Lunch", systemImage: "fork.knife")
                    }
                    Tab(value: RootTab.id) {
                        StudentIDView()
                    } label: {
                        TabLabel("ID", systemImage: "person.text.rectangle")
                    }
                    Tab(value: RootTab.settings) {
                        SettingsView()
                    } label: {
                        TabLabel("Settings", systemImage: "gearshape")
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: navigation.isOnboardingPresented)
        .onOpenURL { navigation.openWidgetURL($0) }
        .background {
            Color.clear
                .fullScreenCover(isPresented: $navigation.isStudentIDScanning,
                                 onDismiss: navigation.studentIDScannerDidDismiss) {
                    if let card = model.studentID {
                        StudentIDScanView(card: card)
                    }
                }
                .id(navigation.studentIDScannerPresentationID)
        }
        .environment(navigation)
        .background {
            SceneWindowReader { window in
                navigation.window = window
                attachNavigation()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { attachNavigation() }
        }
        .preferredColorScheme(model.config.appearance.colorScheme)
        .task {
            // One app-wide 1 Hz heartbeat: flips block boundaries and catches
            // midnight rollover. Cheap — a pure state lookup per tick; the UI
            // only re-renders when a derived value actually changes.
            while !Task.isCancelled {
                model.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func attachNavigation() {
        do { try model.navigation.attach(navigation) }
        catch { navigation.presentError(error) }
    }
}

/// Icons alone in the iOS 26 tab bar; older systems keep the standard titles
/// under each icon. The title stays the item's accessibility label either way.
private struct TabLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        if #available(iOS 26, *) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}

private extension AppearancePref {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
