import SwiftUI
import ScheduleKit

/// Zone 3 — the day's personalized block list, anchored to the present:
/// past dims, current highlights, future stays at full strength.
struct DayTimelineListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let timeline = model.todayTimeline
        // Reading currentSpanID re-renders this list exactly at boundaries.
        let _ = model.currentSpanID
        let now = model.now()
        let pref = model.config.timeFormat
        let blocks = model.config.hideFreePeriods
            ? timeline.blocks.filter { $0.role != .free }
            : timeline.blocks

        VStack(spacing: 6) {
            ForEach(blocks) { block in
                BlockRow(block: block,
                         phase: phase(of: block, at: now),
                         pref: pref)
            }
        }
    }

    private func phase(of block: ResolvedBlock, at now: Date) -> BlockRow.Phase {
        if now >= block.end { return .past }
        if now >= block.start { return .current }
        return .upcoming
    }
}

struct BlockRow: View {
    enum Phase { case past, current, upcoming }

    let block: ResolvedBlock
    let phase: Phase
    let pref: TimeFormatPref

    var body: some View {
        let tint = ScheduleStyle.tint(for: block.role)

        HStack(spacing: 12) {
            Text(TimeDisplay.range(block.start, block.end, pref))
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)

            RoundedRectangle(cornerRadius: 2)
                .fill(phase == .past ? Color.gray.opacity(0.4) : tint)
                .frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(block.displayName)
                    .font(.subheadline.weight(block.role == .free ? .regular : .semibold))
                    .foregroundStyle(block.role == .free ? .secondary : .primary)
                if let room = block.room {
                    Text("Room \(room)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if let half = block.half {
                Text("\(block.periodID.storageKey)\(half.rawValue)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(0.15)))
            }

            if phase == .current {
                Text("NOW")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tint))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(phase == .current ? tint.opacity(0.12) : Color.clear)
        )
        .opacity(phase == .past ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [block.displayName]
        if let room = block.room { parts.append("room \(room)") }
        parts.append("\(TimeDisplay.time(block.start, pref)) to \(TimeDisplay.time(block.end, pref))")
        if phase == .current { parts.append("happening now") }
        if phase == .past { parts.append("finished") }
        return parts.joined(separator: ", ")
    }
}
