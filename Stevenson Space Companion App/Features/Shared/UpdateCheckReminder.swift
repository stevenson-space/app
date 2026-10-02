import SwiftUI

/// A quiet, actionable reminder shown only when a feed's check is overdue.
struct UpdateCheckReminder: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isRequestPending = false

    let title: LocalizedStringKey
    let isChecking: Bool
    var lastError: String? = nil
    let checkForUpdates: () async -> Void

    private var isBusy: Bool { isChecking || isRequestPending }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "wifi")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(StevensonPalette.accent)
                        .frame(width: 36, height: 36)
                        .background(StevensonPalette.accent.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Connect to the internet with the app open to check for anything new.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            if !isBusy, let lastError {
                Text("Couldn't check for updates: \(lastError)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                guard !isBusy else { return }
                isRequestPending = true
                Task {
                    defer { isRequestPending = false }
                    await checkForUpdates()
                }
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                    }
                    Text(isBusy ? "Checking…" : "Check for Updates")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .tint(StevensonPalette.accent)
            .disabled(isBusy)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.primary.opacity(0.05), lineWidth: 1)
        }
    }
}

#Preview("Schedule reminder") {
    UpdateCheckReminder(
        title: "Schedule updates",
        isChecking: false,
        checkForUpdates: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("Lunch reminder · Dark") {
    UpdateCheckReminder(
        title: "Lunch menu updates",
        isChecking: false,
        checkForUpdates: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}

#Preview("Checking with larger text") {
    UpdateCheckReminder(
        title: "Lunch menu updates",
        isChecking: true,
        checkForUpdates: {})
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Failed check") {
    UpdateCheckReminder(
        title: "Schedule updates",
        isChecking: false,
        lastError: "The Internet connection appears to be offline.",
        checkForUpdates: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}
