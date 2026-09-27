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
        TabView(selection: $navigation.selectedTab) {
            Tab("Home", systemImage: "clock", value: RootTab.home) {
                HomeView()
            }
            Tab("Lunch", systemImage: "fork.knife", value: RootTab.lunch) {
                LunchMenuView()
            }
            Tab("ID", systemImage: "person.text.rectangle", value: RootTab.id) {
                StudentIDView()
            }
            Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                SettingsView()
            }
        }
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
