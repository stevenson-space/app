import SwiftUI
import ScheduleKit

/// Zone 1 — the schedule type. Quiet on Standard days; on anything else a
/// gold patch is sewn on, with honest notes for overrides and uncertain
/// rotations.
struct HomeHeaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.jacketGround) private var ground
    @Environment(\.appColorScheme) private var appColorScheme
    let timeline: DayTimeline
    @State private var showsOverrideEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if timeline.isStandardSchedule {
                Text(timeline.scheduleLabel)
                    .font(.subheadline)
                    .foregroundStyle(ground.ink2)
            } else {
                JacketPatch(timeline.scheduleLabel, systemImage: ScheduleStyle.icon(for: timeline.family))
            }

            if let note = timeline.dayNote {
                Text(note)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ground.ink)
            }

            if timeline.provenance == .override {
                note("Set by you as a manual override", systemImage: "pencil")
            }
            if timeline.rotationUncertain {
                Button {
                    showsOverrideEditor = true
                } label: {
                    note("Rotation unverified. Tap to set it.", systemImage: "questionmark.circle",
                         ink: ground.live)
                }
                .buttonStyle(.plain)
            }
            if model.map == nil {
                note("Special schedules not synced yet", systemImage: "wifi.exclamationmark")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showsOverrideEditor) {
            NavigationStack {
                OverrideEditorView(initialDay: timeline.day)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showsOverrideEditor = false }
                        }
                    }
            }
            .environment(\.colorScheme, appColorScheme)
        }
    }

    private func note(_ text: String, systemImage: String, ink: Color? = nil) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(ink ?? ground.ink2)
    }
}
