import SwiftUI
import ScheduleKit

/// Zone 3 — the day's personalized block cards, anchored to the present:
/// past dims, current highlights, the next block carries a countdown chip.
/// Preview days show every block without live status or countdowns.
struct DayTimelineListView: View {
    @Environment(AppModel.self) private var model

    let timeline: DayTimeline
    let isLive: Bool
    var minimumHeight: CGFloat = 0

    var body: some View {
        if isLive {
            liveList
        } else {
            blockList(now: nil)
        }
    }

    private var liveList: some View {
        // Reading currentSpanID re-renders this list exactly at boundaries.
        let _ = model.currentSpanID
        // Per-minute ticks keep the upcoming-block chip honest between boundaries.
        return TimelineView(.periodic(from: .now, by: 60)) { context in
            blockList(now: context.date.addingTimeInterval(model.displayOffset))
        }
    }

    private func blockList(now: Date?) -> some View {
        let config = model.config
        let pref = config.timeFormat
        let blocks = timeline.blocks
        let nextUpcomingID = now.flatMap { instant in
            blocks.first { $0.start > instant }?.id
        }

        return VStack(spacing: 8) {
            ForEach(blocks) { block in
                let isCurrent = now.map { $0 >= block.start && $0 < block.end } ?? false
                ScheduleCardRow(
                    emoji: ScheduleStyle.emoji(for: block, config: config),
                    title: block.displayName,
                    subtitle: subtitle(for: block, pref: pref),
                    periodLabel: periodLabel(for: block),
                    minimumHeight: max(0, (minimumHeight - CGFloat(max(blocks.count - 1, 0)) * 8)
                                       / CGFloat(max(blocks.count, 1))),
                    dimmed: now.map { $0 >= block.end } ?? false,
                    highlightTint: isCurrent ? ScheduleStyle.tint(for: block.role) : nil
                ) {
                    if isCurrent {
                        Text("NOW")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(ScheduleStyle.tint(for: block.role)))
                    } else if let now, block.id == nextUpcomingID {
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

    /// Use the bell schedule identity, not list position or customization identity:
    /// early dismissal can reorder periods and continuation classes can share a name.
    private func periodLabel(for block: ResolvedBlock) -> String? {
        guard let number = block.periodID.periodNumber else { return nil }
        return block.spanLabel ?? String(number)
    }

    /// Period identity has its own label; this line is just time and room.
    private func subtitle(for block: ResolvedBlock, pref: TimeFormatPref) -> String {
        var parts = [TimeDisplay.range(block.start, block.end, pref)]
        if let room = block.room { parts.append(room) }
        return parts.joined(separator: " · ")
    }

    private func accessibilitySummary(for block: ResolvedBlock, now: Date?,
                                      pref: TimeFormatPref) -> String {
        var parts = [block.displayName]
        if let period = periodLabel(for: block) {
            parts.insert("Period \(period)", at: 0)
        }
        if let room = block.room { parts.append("room \(room)") }
        parts.append("\(TimeDisplay.time(block.start, pref)) to \(TimeDisplay.time(block.end, pref))")
        if let now {
            if now >= block.start && now < block.end { parts.append("happening now") }
            if now >= block.end { parts.append("finished") }
        }
        return parts.joined(separator: ", ")
    }
}
