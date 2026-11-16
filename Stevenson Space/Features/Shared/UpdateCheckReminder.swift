import SwiftUI
import ScheduleKit

/// Keeps the optional reminder and its spacing inside the scheduled container.
struct UpdateCheckSection<Content: View>: View {
    @State private var isRequestPending = false
    @State private var didManualCheckFail = false
    @State private var isOverdue = false
    @State private var clockChanges = 0

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
        .task(id: OverdueTimerID(metadata: metadata, clockChanges: clockChanges)) {
            // Task.sleep doesn't follow wall-clock changes, so an early wakeup
            // re-checks and sleeps again until the deadline is reached.
            while true {
                let now = Date()
                isOverdue = metadata.isUpdateCheckOverdue(at: now)
                guard !isOverdue,
                      let deadline = metadata.updateCheckDeadline,
                      deadline > now else { return }
                do {
                    // SwiftUI cancels the wait if the feed is refreshed, the
                    // clock changes, or this section leaves the view hierarchy.
                    try await Task.sleep(for: .seconds(deadline.timeIntervalSince(now)))
                } catch {
                    return
                }
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSSystemClockDidChange) {
                clockChanges += 1
            }
        }
        .onChange(of: metadata.lastSuccess) {
            didManualCheckFail = false
        }
    }
}

/// Restarts the overdue timer when the feed is refreshed or the clock changes.
private struct OverdueTimerID: Equatable {
    let metadata: FetchMetadata
    let clockChanges: Int
}

/// A quiet, actionable reminder shown only when a feed's check is overdue.
/// No card: a stitched rule, a line of text and a capsule button, in the
/// inks of whatever ground it sits on.
struct UpdateCheckReminder: View {
    @Environment(\.jacketGround) private var ground

    let title: LocalizedStringKey
    let isChecking: Bool
    var didManualCheckFail = false
    let checkForUpdates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StitchRule(ground.stitch)
                .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(ground.ink)
                Text("Check for updates to make sure you have the latest information.")
                    .font(.subheadline)
                    .foregroundStyle(ground.ink2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)

            if !isChecking, didManualCheckFail {
                Text("Couldn't check for updates. Please try again later.")
                    .font(.subheadline)
                    .foregroundStyle(ground.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            Button(action: checkForUpdates) {
                HStack(spacing: 8) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(ground.ink)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                    }
                    Text(isChecking ? "Checking…" : "Check for Updates")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ground.ink)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .background(Capsule().fill(ground.ink.opacity(0.12)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isChecking)
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Schedule reminder") {
    UpdateCheckReminder(
        title: "Schedule updates",
        isChecking: false,
        checkForUpdates: {})
        .padding()
        .background(Jacket.lining)
}

#Preview("Lunch reminder · Dark") {
    UpdateCheckReminder(
        title: "Lunch menu updates",
        isChecking: false,
        checkForUpdates: {})
        .padding()
        .background(Jacket.lining)
        .preferredColorScheme(.dark)
}

#Preview("Checking with larger text") {
    UpdateCheckReminder(
        title: "Lunch menu updates",
        isChecking: true,
        checkForUpdates: {})
        .padding()
        .background(Jacket.lining)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Failed check") {
    UpdateCheckReminder(
        title: "Schedule updates",
        isChecking: false,
        didManualCheckFail: true,
        checkForUpdates: {})
        .padding()
        .background(Jacket.lining)
}
