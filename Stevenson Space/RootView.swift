import SwiftUI
import ScheduleKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var navigation: SceneNavigation

    init(model: AppModel) {
        _navigation = State(initialValue: SceneNavigation(model: model))
    }

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.selectedTab) {
            Tab("Home", systemImage: "clock", value: RootTab.home) {
                HomeView()
                    .environment(\.colorScheme, homeColorScheme)
            }
            Tab("Lunch", systemImage: "fork.knife", value: RootTab.lunch) {
                LunchMenuView()
                    .environment(\.colorScheme, colorScheme)
            }
            Tab("ID", systemImage: "person.text.rectangle", value: RootTab.id) {
                StudentIDView()
                    .environment(\.colorScheme, colorScheme)
            }
            Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                SettingsView()
                    .environment(\.colorScheme, colorScheme)
            }
        }
        // The tab bar's glass reads dark over Home's green field; every tab
        // restores the real appearance for its own content above.
        .environment(\.colorScheme, navigation.selectedTab == .home ? homeColorScheme : colorScheme)
        .environment(\.appColorScheme, colorScheme)
        .tint(tabTint)
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

    /// Home's chrome (toolbar and tab bar glass) is dark over the green field
    /// in either appearance; light glass over it washes out to mint.
    private var homeColorScheme: ColorScheme {
        navigation.homeGround == .field ? .dark : colorScheme
    }

    /// The selected tab reads in the ground's ink on Home's field and gold
    /// side; everywhere else it is the accent.
    private var tabTint: Color {
        guard navigation.selectedTab == .home, navigation.homeGround != .lining else {
            return Jacket.accent
        }
        return navigation.homeGround.ink
    }

    private func attachNavigation() {
        do { try model.navigation.attach(navigation) }
        catch { presentNavigationError(error) }
    }

    private func presentNavigationError(_ error: Error) {
        guard var presenter = navigation.window?.rootViewController else { return }
        // A pending intent can fail because a sheet is open. Present from that
        // sheet so the error remains visible without discarding unfinished edits.
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        if let transition = presenter.transitionCoordinator {
            transition.animate(alongsideTransition: nil) { _ in
                DispatchQueue.main.async { presentNavigationError(error) }
            }
            return
        }
        let alert = UIAlertController(title: "Could not show your student ID",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        presenter.present(alert, animated: true)
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
