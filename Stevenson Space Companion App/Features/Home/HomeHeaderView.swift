import SwiftUI
import ScheduleKit

/// Zone 1 — the schedule-type indicator. Quiet on Standard days, loud on
/// anything else, with honesty badges for overrides and uncertain rotations.
struct HomeHeaderView: View {
    @Environment(AppModel.self) private var model
    let timeline: DayTimeline

    var body: some View {
        let isStandard = timeline.isStandardSchedule

        VStack(alignment: .leading, spacing: 8) {
            if isStandard {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(timeline.scheduleLabel)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                let accent = ScheduleStyle.accent(for: timeline.family)
                Label(timeline.scheduleLabel, systemImage: ScheduleStyle.icon(for: timeline.family))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(accent))
            }

            if let note = timeline.dayNote {
                Text(note)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(ScheduleStyle.accent(for: timeline.family))
            }

            badges
            dataFreshnessLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var badges: some View {
        HStack(spacing: 8) {
            if timeline.provenance == .override {
                badge("Manual override", icon: "pencil", tint: .blue)
            }
            if timeline.rotationUncertain {
                Button {
                    model.selectedTab = .settings
                } label: {
                    badge("Rotation unverified — tap to fix", icon: "questionmark.circle", tint: .orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func badge(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.15)))
    }

    @ViewBuilder private var dataFreshnessLine: some View {
        if model.map == nil {
            Label("Special schedules not synced yet — the app will fetch them when it's online.",
                  systemImage: "wifi.slash")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let lastChanged = model.fetchMetadata.lastChanged {
            Label("Schedule updated \(lastChanged.formatted(.relative(presentation: .named)))",
                  systemImage: "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
