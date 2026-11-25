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
                Label("Student ID", systemImage: "barcode.viewfinder")
                    .controlWidgetActionHint("Show Student ID")
            }
            .tint(.accentColor)
        }
        .displayName("Student ID")
        .description("Show your ID barcode full screen for scanning.")
    }
}
