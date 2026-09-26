import SwiftUI
import ScheduleKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation: SceneNavigation
    @State private var navigationError: String?

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
        .alert("Could not show your student ID", isPresented: Binding(
            get: { navigationError != nil },
            set: { if !$0 { navigationError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(navigationError ?? "")
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
        catch { navigationError = error.localizedDescription }
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
