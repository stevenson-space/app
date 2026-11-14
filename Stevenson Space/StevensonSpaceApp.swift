//
//  StevensonSpaceApp.swift
//  Stevenson Space
//

import SwiftUI
import ScheduleKit
import AppIntents

@main
struct StevensonSpaceApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        AppDependencyManager.shared.add(dependency: model)
        StevensonShortcuts.updateAppShortcutParameters()
        // A neutral selected tab, like Instagram's. Set on the tab bar alone:
        // a SwiftUI tint on the TabView would also recolor every screen in it,
        // and the TabView overrides UITabBar.tintColor with its own accent.
        let tabBar = UITabBarAppearance()
        for item in [tabBar.stackedLayoutAppearance, tabBar.inlineLayoutAppearance,
                     tabBar.compactInlineLayoutAppearance] {
            item.selected.iconColor = .label
        }
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .environment(model)
        }
        // `initial: true` matters on a cold launch: when the scene is already
        // active by the time this observer is installed, a change-only handler
        // never fires and the app runs the whole session on cached data.
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.handleScenePhase(phase)
        }
    }
}
