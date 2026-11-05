import SwiftUI
import ScheduleKit

/// Zone 3 — the day's personalized blocks, anchored to the present: past
/// rows quiet, the current block sewn on as a patch, the next block carrying
/// a countdown cue. During a passing period the block being walked to is the
/// patch. Preview days show every block without live status.
struct DayTimelineListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.jacketGround) private var ground

    let timeline: DayTimeline
    let isLive: Bool
    let title: String
    var minimumHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .jacketLabel()
                .foregroundStyle(ground.ink2)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            if isLive {
                liveList
            } else {
                blockList(now: nil)
            }
        }
    }

    private var liveList: some View {
        // Reading currentSpanID re-renders this list exactly at boundaries.
        let _ = model.currentSpanID
        // Per-minute ticks keep the upcoming-block cue honest between boundaries.
        return TimelineView(.periodic(from: .now, by: 60)) { context in
            blockList(now: context.date.addingTimeInterval(model.displayOffset))
        }
    }

    private func blockList(now: Date?) -> some View {
        let config = model.config
        let pref = config.timeFormat
        let blocks = timeline.blocks
        let currentID = now.flatMap { instant in
            blocks.first { instant >= $0.start && instant < $0.end }?.id
        }
        let nextUpcomingID = now.flatMap { instant in
            blocks.first { $0.start > instant }?.id
        }
        // Between bells, the block being walked to is the patch.
        let patchID = currentID ?? (ground == .gold ? nextUpcomingID : nil)
        let rowHeight = max(0, minimumHeight / CGFloat(max(blocks.count, 1)))

        return VStack(spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                let isPatch = block.id == patchID
                let touchesPatch = isPatch || (index > 0 && blocks[index - 1].id == patchID)
                if index > 0 && !touchesPatch {
                    RowStitch()
                }
                ScheduleRow(
                    // The bell schedule identity, not list position or customization
                    // identity: early dismissal can reorder periods and continuation
                    // classes can share a name.
                    periodLabel: block.periodLabel,
                    emoji: emoji(for: block, config: config),
                    title: block.displayName,
                    subtitle: subtitle(for: block, pref: pref),
                    emphasis: isPatch ? .patch : (now.map { $0 >= block.end } ?? false) ? .past : .normal,
                    minimumHeight: rowHeight
                ) {
                    if isPatch {
                        RowCue(text: block.id == currentID ? "Now" : "Next", onPatch: true)
                    } else if let now, block.id == nextUpcomingID {
                        RowCue(text: TimeDisplay.untilChip(block.start.timeIntervalSince(now)))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary(for: block, now: now, pref: pref))
            }
        }
    }

    /// Classes show the student's emoji; lunch, free and the rest are named
    /// plainly, so the emoji stays the student's own content.
    private func emoji(for block: ResolvedBlock, config: UserConfig) -> String? {
        block.role == .classPeriod ? ScheduleStyle.emoji(for: block, config: config) : nil
    }

    /// Period identity has its own column; this line is just time and room.
    private func subtitle(for block: ResolvedBlock, pref: TimeFormatPref) -> String {
        var parts = [TimeDisplay.range(block.start, block.end, pref)]
        if let room = block.room { parts.append(room) }
        return parts.joined(separator: " · ")
    }

    private func accessibilitySummary(for block: ResolvedBlock, now: Date?,
                                      pref: TimeFormatPref) -> String {
        var parts = [block.displayName]
        if let period = block.periodLabel {
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
