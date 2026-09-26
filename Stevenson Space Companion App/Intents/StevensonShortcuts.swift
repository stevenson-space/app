import AppIntents

struct StevensonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShowStudentIDIntent(), phrases: [
            "Show my student ID in \(.applicationName)",
            "Scan my ID with \(.applicationName)",
        ], shortTitle: "Show Student ID", systemImageName: "barcode.viewfinder")

        AppShortcut(intent: GetCurrentClassIntent(), phrases: [
            "What's my current class in \(.applicationName)",
            "Where is my current class in \(.applicationName)",
        ], shortTitle: "Current Class", systemImageName: "book")

        AppShortcut(intent: GetCurrentPeriodIntent(), phrases: [
            "What period is it in \(.applicationName)",
        ], shortTitle: "Current Period", systemImageName: "clock")

        AppShortcut(intent: GetNextClassIntent(), phrases: [
            "What's my next class in \(.applicationName)",
            "Where is my next class in \(.applicationName)",
        ], shortTitle: "Next Class", systemImageName: "arrow.right.circle")

        AppShortcut(intent: GetLunchMenuIntent(), phrases: [
            "What's for lunch in \(.applicationName)",
        ], shortTitle: "Lunch Menu", systemImageName: "fork.knife")

        AppShortcut(intent: GetScheduleIntent(), phrases: [
            "Show my schedule in \(.applicationName)",
        ], shortTitle: "Today's Schedule", systemImageName: "calendar")

        AppShortcut(intent: GetScheduleTypeIntent(), phrases: [
            "What's today's schedule type in \(.applicationName)",
        ], shortTitle: "Schedule Type", systemImageName: "calendar.badge.clock")

        AppShortcut(intent: OpenAppTabIntent(), phrases: [
            "Open \(\.$tab) in \(.applicationName)",
        ], shortTitle: "Open Tab", systemImageName: "square.grid.2x2")
    }
}
