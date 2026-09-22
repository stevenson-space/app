import AppIntents

enum AppTab: String, AppEnum {
    case home, lunch, id, settings

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tab"
    static let caseDisplayRepresentations: [AppTab: DisplayRepresentation] = [
        .home: "Home", .lunch: "Lunch", .id: "ID", .settings: "Settings",
    ]

    var rootTab: RootTab {
        switch self {
        case .home: .home
        case .lunch: .lunch
        case .id: .id
        case .settings: .settings
        }
    }
}

struct OpenAppTabIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Tab"
    static let description = IntentDescription("Open Home, Lunch, ID, or Settings in Stevenson Space.")
    static let openAppWhenRun = true
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Tab", default: .home) var tab: AppTab
    @AppDependency private var model: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$tab)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        model.openTab(tab.rootTab)
        return .result()
    }
}

struct ShowStudentIDIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Student ID"
    static let description = IntentDescription(
        "Open your student ID barcode and number full screen for scanning. If no ID is saved, open the ID setup screen.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @AppDependency private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if try model.openStudentIDScanner() {
            return .result(dialog: "Here is your student ID.")
        }
        return .result(dialog: "Import your student ID screenshot in the ID tab first.")
    }
}
