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
                    .environment(\.colorScheme, homeColorScheme)
            } label: {
                TabLabel("Home", systemImage: "clock")
            }
            Tab(value: RootTab.lunch) {
                LunchMenuView()
                    .environment(\.colorScheme, colorScheme)
            } label: {
                TabLabel("Lunch", systemImage: "fork.knife")
            }
            Tab(value: RootTab.id) {
                StudentIDView()
                    .environment(\.colorScheme, colorScheme)
            } label: {
                TabLabel("ID", systemImage: "person.text.rectangle")
            }
            Tab(value: RootTab.settings) {
                SettingsView()
                    .environment(\.colorScheme, colorScheme)
            } label: {
                TabLabel("Settings", systemImage: "gearshape")
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
    /// side; everywhere else it is the accent. The iOS 26 icon-only bar takes
    /// a neutral selected icon from its appearance instead (see
    /// `StevensonSpaceApp`), so this colours the bar only before iOS 26.
    private var tabTint: Color {
        guard navigation.selectedTab == .home, navigation.homeGround != .lining else {
            return Jacket.accent
        }
        return navigation.homeGround.ink
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
