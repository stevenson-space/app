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
        #if DEBUG
        Self.applyTimeTravelArgument(to: model)
        #endif
        _model = State(initialValue: model)
        AppDependencyManager.shared.add(dependency: model)
        JacketAppearance.configure()
        StevensonShortcuts.updateAppShortcutParameters()
        // A neutral selected tab for the iOS 26 icon-only bar, like Instagram's;
        // older systems keep the standard tab bar. Set on the tab bar alone: a
        // SwiftUI tint on the TabView would also recolor every screen in it, and
        // the TabView overrides UITabBar.tintColor with its own accent. The
        // scroll-edge appearance stays nil, so UIKit derives it from this one.
        if #available(iOS 26, *) {
            let tabBar = UITabBarAppearance()
            for item in [tabBar.stackedLayoutAppearance, tabBar.inlineLayoutAppearance,
                         tabBar.compactInlineLayoutAppearance] {
                item.selected.iconColor = .label
            }
            UITabBar.appearance().standardAppearance = tabBar
        }
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

    #if DEBUG
    /// `-SSTimeTravel 2026-09-14T10:52:19` starts the DEBUG clock at that
    /// school-time instant, so a screenshot or a simulator check can open
    /// straight into any Home state.
    private static func applyTimeTravelArgument(to model: AppModel) {
        guard let value = UserDefaults.standard.string(forKey: "SSTimeTravel") else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = SchoolTime.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let instant = formatter.date(from: value) else { return }
        model.timeTravelOffset = instant.timeIntervalSinceNow
    }
    #endif
}
