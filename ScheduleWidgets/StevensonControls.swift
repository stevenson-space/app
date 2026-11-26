import AppIntents
import SwiftUI
import WidgetKit

/// Opens the full-screen ID barcode from Control Center, the Lock Screen, or
/// the Action button, without a custom shortcut. With no saved ID, it opens
/// the ID setup screen.
struct StudentIDControl: ControlWidget {
    static let kind = "StudentIDControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenControlScreenIntent(.studentID)) {
                Label("Student ID", systemImage: "person.text.rectangle")
                    .controlWidgetActionHint("Show Student ID")
            }
            .tint(.accentColor)
        }
        .displayName("Student ID")
        .description("Show your ID barcode full screen for scanning.")
    }
}

/// Opens Home at today's schedule.
struct ScheduleControl: ControlWidget {
    static let kind = "ScheduleControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenControlScreenIntent(.schedule)) {
                Label("Schedule", systemImage: "calendar.badge.clock")
                    .controlWidgetActionHint("Show Schedule")
            }
            .tint(.accentColor)
        }
        .displayName("Schedule")
        .description("See today's classes and the time until the bell.")
    }
}

/// Opens Lunch at today's menu.
struct LunchMenuControl: ControlWidget {
    static let kind = "LunchMenuControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenControlScreenIntent(.lunch)) {
                Label("Lunch Menu", systemImage: "fork.knife")
                    .controlWidgetActionHint("Show Lunch Menu")
            }
            .tint(.accentColor)
        }
        .displayName("Lunch Menu")
        .description("See what's for lunch today.")
    }
}
