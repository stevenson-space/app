//
//  Stevenson_Space_Companion_AppApp.swift
//  Stevenson Space Companion App
//

import SwiftUI
import ScheduleKit

@main
struct Stevenson_Space_Companion_AppApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
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
