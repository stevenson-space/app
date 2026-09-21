import SwiftUI
import ScheduleKit

/// Zone 1 — the schedule-type indicator. Quiet on Standard days, loud on
/// anything else, with honesty badges for overrides and uncertain rotations.
struct HomeHeaderView: View {
    @Environment(AppModel.self) private var model
    let timeline: DayTimeline
    @Binding var showsHalfPeriods: Bool
    @State private var showsOverrideEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    scheduleLabel
                    Spacer(minLength: 0)
                    halfPeriodToggle
                }
                VStack(alignment: .leading, spacing: 4) {
                    scheduleLabel
                    halfPeriodToggle
                }
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
        .sheet(isPresented: $showsOverrideEditor) {
            NavigationStack {
                OverrideEditorView(initialDay: timeline.day)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showsOverrideEditor = false }
                        }
                    }
            }
        }
    }

    @ViewBuilder private var scheduleLabel: some View {
        if timeline.isStandardSchedule {
            Label(timeline.scheduleLabel, systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Label(timeline.scheduleLabel, systemImage: ScheduleStyle.icon(for: timeline.family))
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(ScheduleStyle.accent(for: timeline.family)))
        }
    }

    @ViewBuilder private var halfPeriodToggle: some View {
        if let family = timeline.family,
           model.catalog.schedule(family: family, rotation: timeline.rotation)?.hasABVariants == true {
            Toggle("Half periods", isOn: $showsHalfPeriods)
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .font(.caption.weight(.medium))
                .controlSize(.small)
                .frame(minHeight: 44)
                .accessibilityHint("Shows each period’s A and B bell times in the schedule list")
        }
    }

    @ViewBuilder private var badges: some View {
        HStack(spacing: 8) {
            if timeline.provenance == .override {
                badge("Manual override", icon: "pencil", tint: .blue)
            }
            if timeline.rotationUncertain {
                Button {
                    showsOverrideEditor = true
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
