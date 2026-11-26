import AppIntents

/// A screen that a control in Control Center, on the Lock Screen, or on the
/// Action button opens.
enum ControlScreen: String, AppEnum {
    case studentID, schedule, lunch

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"
    static let caseDisplayRepresentations: [ControlScreen: DisplayRepresentation] = [
        .studentID: "Student ID", .schedule: "Schedule", .lunch: "Lunch Menu",
    ]
}

/// Controls open the app through an `OpenIntent`, which has to be a member of
/// both the app and the widget extension. The system brings the app forward
/// and runs `perform()` there, so the extension's copy never navigates.
struct OpenControlScreenIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Screen"
    // Shortcuts and Siri already offer Show Student ID and Open Tab.
    static let isDiscoverable = false
    // Matches Show Student ID: the ID never opens on a locked device.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Screen") var target: ControlScreen

    #if !WIDGET_EXTENSION
    @AppDependency private var model: AppModel
    #endif

    init() {}

    init(_ target: ControlScreen) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        switch target {
        case .studentID:
            // Siri and Shortcuts speak this error; a control shows it in the app.
            do { try model.navigation.openStudentIDScanner() }
            catch { model.navigation.presentError(error) }
        case .schedule: model.navigation.openTab(.home)
        case .lunch: model.navigation.openTab(.lunch)
        }
        #endif
        return .result()
    }
}
