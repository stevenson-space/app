import SwiftUI
import ScheduleKit

/// Keeps the optional reminder and its spacing inside the scheduled container.
struct UpdateCheckSection<Content: View>: View {
    @State private var isRequestPending = false
    @State private var didManualCheckFail = false
    @State private var isOverdue = false

    let title: LocalizedStringKey
    let metadata: FetchMetadata
    let isChecking: Bool
    let spacing: CGFloat
    let checkForUpdates: () async -> Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: spacing) {
            content()
            // Use the real clock, independent of the selected day and DEBUG
            // time travel. Automatic checks need no user action.
            if isOverdue, metadata.isUpdateCheckOverdue(at: Date()),
               !isChecking || isRequestPending {
                UpdateCheckReminder(
                    title: title,
                    isChecking: isChecking || isRequestPending,
                    didManualCheckFail: didManualCheckFail
                ) {
                    guard !isChecking, !isRequestPending else { return }
                    isRequestPending = true
                    didManualCheckFail = false
                    Task {
                        didManualCheckFail = !(await checkForUpdates())
                        isRequestPending = false
                    }
                }
            }
        }
        .task(id: metadata) {
            let now = Date()
            isOverdue = metadata.isUpdateCheckOverdue(at: now)
            guard !isOverdue,
                  let deadline = metadata.updateCheckDeadline,
                  deadline > now else { return }
            do {
                // One wakeup at the deadline; SwiftUI cancels it if the feed
                // is refreshed or this section leaves the view hierarchy.
                try await Task.sleep(for: .seconds(deadline.timeIntervalSince(now)))
                isOverdue = metadata.isUpdateCheckOverdue(at: Date())
            } catch {
                return
            }
        }
        .onChange(of: metadata.lastSuccess) {
            didManualCheckFail = false
        }
    }
}

/// A quiet, actionable reminder shown only when a feed's check is overdue.
struct UpdateCheckReminder: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: LocalizedStringKey
    let isChecking: Bool
    var didManualCheckFail = false
    let checkForUpdates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "arrow.clockwise")
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
                    Text("Check for updates to make sure you have the latest information.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            if !isChecking, didManualCheckFail {
                Text("Couldn't check for updates. Please try again later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: checkForUpdates) {
                HStack(spacing: 8) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                    }
                    Text(isChecking ? "Checking…" : "Check for Updates")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .tint(StevensonPalette.accent)
            .disabled(isChecking)
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
        didManualCheckFail: true,
        checkForUpdates: {})
        .padding()
        .background(Color(.systemGroupedBackground))
}
