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
        .onChange(of: scenePhase) { _, phase in
            model.handleScenePhase(phase)
        }
    }
}
