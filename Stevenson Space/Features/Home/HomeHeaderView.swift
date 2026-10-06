import SwiftUI
import ScheduleKit

/// Zone 1 — the schedule-type indicator. Quiet on Standard days, loud on
/// anything else, with honesty badges for overrides and uncertain rotations.
struct HomeHeaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    let timeline: DayTimeline
    @State private var showsOverrideEditor = false

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
                let accent = scheduleBadgeFill
                Label(timeline.scheduleLabel, systemImage: ScheduleStyle.icon(for: timeline.family))
                    .font(.headline)
                    .foregroundStyle(.contrasting(on: accent))
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

            if model.map == nil {
                Label("Special schedules not synced yet", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
    }

    /// Opaque badge fills, separate from the adaptive accents used for text
    /// elsewhere. Each custom fill gives white text at least 4.5:1 contrast.
    private var scheduleBadgeFill: Color {
        switch timeline.family {
        case .lateArrival:
            // Match the increased-contrast purple in both appearances/settings.
            return Color(.sRGB, red: 176 / 255, green: 47 / 255, blue: 194 / 255)
        case .odyssey:
            return contrast == .increased
                ? Color(.sRGB, red: 144 / 255, green: 37 / 255, blue: 72 / 255)
                : Color(.sRGB, red: 174 / 255, green: 52 / 255, blue: 91 / 255)
        case .activityPeriod where contrast == .increased:
            return Color(.sRGB, red: 0, green: 101 / 255, blue: 113 / 255)
        case .pmAssembly where contrast == .increased:
            return Color(.sRGB, red: 157 / 255, green: 66 / 255, blue: 14 / 255)
        default:
            return ScheduleStyle.accent(for: timeline.family)
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

    /// Only the icon takes the tint: tinted caption text on its own tinted
    /// fill stays under 4.5:1 in light mode, even with Increase Contrast.
    private func badge(_ text: String, icon: String, tint: Color) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.15)))
    }
}
