import AppIntents

/// The intent's target is deliberately a fixed, non-PII destination. Student
/// ID profile fields never cross the App Intents boundary.
enum StudentIDIntentDestination: String, AppEnum, CaseIterable, Sendable {
    case studentID

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Destination"
    }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.studentID: "Student ID"]
    }
}

struct ShowStudentIDIntent: OpenIntent {
    static let title: LocalizedStringResource = "Show Student ID"
    static let description = IntentDescription("Open the Student ID tab in Stevenson Space.")

    @Parameter(title: "Destination", default: .studentID)
    var target: StudentIDIntentDestination

    static var parameterSummary: some ParameterSummary {
        Summary("Show Student ID")
    }

    func perform() async throws -> some IntentResult {
        // OpenIntent brings the app to the foreground on both a cold and a
        // running invocation. This handoff only carries a destination token.
        await MainActor.run {
            AppIntentRouter.shared.enqueue(.studentID)
        }
        return .result()
    }
}

// `supportedModes` is introduced for iOS 26. On earlier supported OSes,
// OpenIntent supplies the equivalent foreground behavior.
@available(iOS 26.0, *)
extension ShowStudentIDIntent {
    static let supportedModes: IntentModes = .foreground(.immediate)
}

struct StevensonSpaceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowStudentIDIntent(),
            phrases: [
                "Show my student ID in \(.applicationName)",
                "Open my student ID in \(.applicationName)",
            ],
            shortTitle: "Show Student ID",
            systemImageName: "person.text.rectangle"
        )
    }
}
