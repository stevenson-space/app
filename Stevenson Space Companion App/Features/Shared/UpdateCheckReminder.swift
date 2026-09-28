import SwiftUI

/// A quiet, actionable reminder shown only when a feed's check is overdue.
struct UpdateCheckReminder: View {
    let message: LocalizedStringKey
    let isChecking: Bool
    let checkForUpdates: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "wifi")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(isChecking ? "Checking…" : "Check for Updates") {
                Task { await checkForUpdates() }
            }
            .buttonStyle(.bordered)
            .disabled(isChecking)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Update check reminder") {
    UpdateCheckReminder(
        message: "It's been a while since we could check for schedule updates. Connect to the internet with the app open, then check again.",
        isChecking: false,
        checkForUpdates: {})
        .padding()
}

#Preview("Checking with larger text") {
    UpdateCheckReminder(
        message: "It's been a while since we could check for lunch menu updates. Connect to the internet with the app open, then check again.",
        isChecking: true,
        checkForUpdates: {})
        .padding()
        .environment(\.dynamicTypeSize, .accessibility3)
}
