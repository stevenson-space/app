import SwiftUI
import ScheduleKit

/// Zone 3 — the day's personalized block cards, anchored to the present:
/// past dims, current highlights, the next block carries a countdown chip.
struct DayTimelineListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let timeline = model.todayTimeline
        // Reading currentSpanID re-renders this list exactly at boundaries.
        let _ = model.currentSpanID
        let config = model.config
        let pref = config.timeFormat
        let blocks = config.hideFreePeriods
            ? timeline.blocks.filter { $0.role != .free }
            : timeline.blocks

        // Per-minute ticks keep the "In 1h 12m" chip honest between boundaries.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date.addingTimeInterval(model.displayOffset)
            let nextUpcomingID = blocks.first { $0.start > now }?.id

            VStack(spacing: 8) {
                ForEach(blocks) { block in
                    let isCurrent = now >= block.start && now < block.end
                    ScheduleCardRow(
                        emoji: ScheduleStyle.emoji(for: block, config: config),
                        title: block.displayName,
                        subtitle: subtitle(for: block, pref: pref),
                        dimmed: now >= block.end,
                        highlightTint: isCurrent ? ScheduleStyle.tint(for: block.role) : nil
                    ) {
                        if isCurrent {
                            Text("NOW")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(ScheduleStyle.tint(for: block.role)))
                        } else if block.id == nextUpcomingID {
                            Text(TimeDisplay.untilChip(block.start.timeIntervalSince(now)))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilitySummary(for: block, now: now, pref: pref))
                }
            }
        }
    }

    /// "9:26 – 10:38 · 2–3A · 118" — span only when the block isn't a plain
    /// full period, room only when set.
    private func subtitle(for block: ResolvedBlock, pref: TimeFormatPref) -> String {
        var parts = [TimeDisplay.range(block.start, block.end, pref)]
        if let spanLabel = block.spanLabel { parts.append(spanLabel) }
        if let room = block.room { parts.append(room) }
        return parts.joined(separator: " · ")
    }

    private func accessibilitySummary(for block: ResolvedBlock, now: Date,
                                      pref: TimeFormatPref) -> String {
        var parts = [block.displayName]
        if let room = block.room { parts.append("room \(room)") }
        parts.append("\(TimeDisplay.time(block.start, pref)) to \(TimeDisplay.time(block.end, pref))")
        if now >= block.start && now < block.end { parts.append("happening now") }
        if now >= block.end { parts.append("finished") }
        return parts.joined(separator: ", ")
    }
}
