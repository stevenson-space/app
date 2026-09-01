import SwiftUI
import ScheduleKit

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab("Home", systemImage: "clock", value: RootTab.home) {
                HomeView()
            }
            Tab("Lunch", systemImage: "fork.knife", value: RootTab.lunch) {
                LunchMenuView()
            }
            Tab("ID", systemImage: "person.text.rectangle", value: RootTab.studentID) {
                StudentIDView()
            }
            Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                SettingsView()
            }
        }
        .preferredColorScheme(model.config.appearance.colorScheme)
        .onChange(of: model.intentRouter.pendingRequest?.id, initial: true) { _, _ in
            model.consumePendingIntent()
        }
        .task {
            // Covers a cold launch where the intent was handled while the
            // scene was still being constructed.
            model.consumePendingIntent()

            // One app-wide 1 Hz heartbeat: flips block boundaries and catches
            // midnight rollover. Cheap — a pure state lookup per tick; the UI
            // only re-renders when a derived value actually changes.
            while !Task.isCancelled {
                model.tick()
                try? await Task.sleep(for: .seconds(1))
            }
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
