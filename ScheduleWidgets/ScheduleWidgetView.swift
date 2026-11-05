import ScheduleKit
import SwiftUI
import UIKit
import WidgetKit

struct ScheduleWidgetView: View {
    let entry: ScheduleWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 42

    private var rectangular: Bool { family == .accessoryRectangular }
    private var medium: Bool { family == .systemMedium }
    private var format: TimeFormatPref { entry.config.timeFormat }
    /// The jacket inks need the jacket ground behind them. Tinted and clear
    /// modes drop the colour, and StandBy can drop the background while
    /// staying full colour; all of them keep the system inks.
    private var fullColor: Bool { renderingMode == .fullColor && showsBackground }
    /// The jacket ground under a full-colour widget.
    private var ground: JacketGround { ScheduleWidgetBackground.ground(for: entry) }
    private var ink: Color { fullColor ? ground.ink : .primary }
    private var ink2: Color { fullColor ? ground.ink2 : .secondary }
    /// The varsity number's twill edge, in full colour only.
    private var twillEdge: Color { fullColor ? ground.heroEdge : .clear }

    var body: some View {
        Group {
            if family == .accessoryCircular {
                CircularScheduleView(entry: entry)
            } else if let schedule = entry.schedule {
                if family == .systemLarge {
                    large(schedule)
                } else if let focus = schedule.focus {
                    active(schedule, focus: focus)
                } else {
                    resting(schedule)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Open Stevenson Space", systemImage: "calendar.badge.exclamationmark")
                        .font(.headline)
                    Text("Open the app to share your schedule.")
                        .font(.caption)
                }
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityHint("Opens today’s schedule in Stevenson Space")
    }

    /// The one live cue: gold ink on the field, dark ink on the gold side.
    private func accent(_ schedule: WidgetScheduleEntry, focus: ResolvedBlock) -> Color {
        fullColor ? ground.live : .primary
    }

    private func active(_ schedule: WidgetScheduleEntry, focus: ResolvedBlock) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: rectangular || typeSize.isAccessibilitySize ? 1 : 5) {
                Text(schedule.widgetCaption())
                    .font(rectangular ? .caption2 : .system(.caption2, weight: .bold).width(.expanded))
                    .textCase(rectangular ? nil : .uppercase)
                    .tracking(rectangular ? 0 : 0.8)
                    .foregroundStyle(accent(schedule, focus: focus))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let interval = entry.countdownInterval {
                    Text(timerInterval: interval, pauseTime: entry.countdownPauseTime, countsDown: true)
                        .font(rectangular ? .varsity(.title2) : .varsity(size: min(timerSize, 44)))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(fullColor ? ground.heroFace : .primary)
                        .twill(twillEdge, x: rectangular ? 0 : 2, y: rectangular ? 0 : 3)
                        .contentTransition(.identity)
                } else {
                    Text(TimeDisplay.time(focus.start, format))
                        .font(rectangular ? .varsity(.title3) : .varsity(.title))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(fullColor ? ground.heroFace : .primary)
                        .twill(twillEdge, x: rectangular ? 0 : 1.5, y: rectangular ? 0 : 2)
                }
                periodName(focus)
                    .font(rectangular ? .caption.weight(.semibold) : .headline)
                    .lineLimit(rectangular || typeSize.isAccessibilitySize ? 1 : 2)
                if typeSize.isAccessibilitySize {
                    if !rectangular, let room = focus.room {
                        Text("Room \(room)").font(.caption2).lineLimit(1)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        Text(details(focus))
                        if let room = focus.room { Text("Room \(room)") }
                        Text(TimeDisplay.range(focus.start, focus.end, format))
                    }
                    .font(.caption2)
                    .foregroundStyle(ink2)
                    .lineLimit(1)
                }
                if schedule.isLeadIn, !medium, !rectangular, !typeSize.isAccessibilitySize {
                    Text(schedule.timeline.scheduleLabel)
                        .font(.caption2).foregroundStyle(ink2).lineLimit(1)
                }
            }
            .accessibilityElement(children: .contain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if medium {
                VerticalStitch(color: fullColor ? ground.stitch : Color.primary.opacity(0.25))
                VStack(alignment: .leading, spacing: 6) {
                    if let next = schedule.upcoming {
                        Text("Up next").widgetLabel().foregroundStyle(ink2)
                        periodName(next).font(.subheadline.weight(.semibold)).lineLimit(3)
                        if let room = next.room { Text("Room \(room)").font(.caption).lineLimit(1) }
                        Text(TimeDisplay.time(next.start, format)).font(.caption).foregroundStyle(ink2)
                    } else {
                        Text("Last period").widgetLabel().foregroundStyle(ink2)
                        Text("School finishes at \(TimeDisplay.time(focus.end, format))")
                            .font(.subheadline).lineLimit(3)
                    }
                    Text(schedule.timeline.scheduleLabel).font(.caption2).foregroundStyle(ink2).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func large(_ schedule: WidgetScheduleEntry) -> some View {
        let preview = schedule.timeline.blocks.isEmpty ? schedule.nextSchoolDay : nil
        let timeline = preview ?? schedule.timeline
        return VStack(alignment: .leading, spacing: 12) {
            if let focus = schedule.focus {
                largeHeader(schedule, focus: focus)
            } else if schedule.isFinished {
                Label("School finished", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold())
                    .padding(.vertical, 8)
            } else if !schedule.timeline.blocks.isEmpty {
                compactResting(schedule)
            } else if let preview, !preview.blocks.isEmpty {
                largeRestingHeader(schedule, next: preview)
            } else {
                resting(schedule)
            }

            if !timeline.blocks.isEmpty {
                HStack {
                    Text(preview == nil ? "Today" : "Next school day")
                        .widgetLabel()
                    Spacer(minLength: 8)
                    Text(timeline.scheduleLabel)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 4)

                // Prefer generous rows, then tighten spacing for split days.
                // The final fallback still includes every block in two columns.
                GeometryReader { geometry in
                    let blocks = timeline.blocks
                    let spaciousHeight = CGFloat(blocks.count * 24 + max(0, blocks.count - 1) * 2)
                    // Choose expanding rows using the actual available height;
                    // ViewThatFits measures ideal size and can select tight rows
                    // even when there is room left beneath them.
                    if geometry.size.height >= spaciousHeight {
                        dayRows(blocks, schedule: schedule, compact: false, spacious: true)
                            .frame(height: geometry.size.height)
                    } else {
                        ViewThatFits(in: .vertical) {
                            dayRows(blocks, schedule: schedule, compact: false)
                            HStack(alignment: .top, spacing: 12) {
                                let midpoint = (blocks.count + 1) / 2
                                dayRows(Array(blocks.prefix(midpoint)), schedule: schedule, compact: true)
                                dayRows(Array(blocks.dropFirst(midpoint)), schedule: schedule, compact: true)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        // Keep the entire day visible; VoiceOver retains full row details.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private func largeRestingHeader(_ schedule: WidgetScheduleEntry, next: DayTimeline) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(status(schedule))
                    .font(.title3.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                patriot(height: 30)
            }
            if case .unknownSchedule(let name) = schedule.state {
                Text(name).font(.caption).foregroundStyle(ink2).lineLimit(1)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Back to school")
                        .widgetLabel()
                        .foregroundStyle(ink2)
                    Text(TimeDisplay.shortDayLabel(next.day))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let start = next.firstBell {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(TimeDisplay.time(start, format))
                            .font(.varsity(.title3))
                        Text("first bell")
                            .font(.caption2)
                            .foregroundStyle(ink2)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(fullColor ? Jacket.twill : Color.primary)
                    .frame(width: 3)
                    .widgetAccentable()
            }
        }
    }

    private func largeHeader(_ schedule: WidgetScheduleEntry, focus: ResolvedBlock) -> some View {
        let tint = accent(schedule, focus: focus)
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(focus.start > schedule.date ? "Up next" : "In progress")
                    .widgetLabel()
                    .foregroundStyle(tint)
                    .widgetAccentable()
                periodName(focus)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)
                Text(details(focus))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ink2)
                    .lineLimit(2)
            }
            .privacySensitive()
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                if let interval = entry.countdownInterval {
                    Text(timerInterval: interval, pauseTime: entry.countdownPauseTime, countsDown: true)
                        .font(.varsity(size: 32))
                        .monospacedDigit()
                        .foregroundStyle(fullColor ? ground.heroFace : .primary)
                        .twill(twillEdge, x: 1.5, y: 2)
                        .contentTransition(.identity)
                        .multilineTextAlignment(.trailing)
                    Text(focus.start > schedule.date ? "until start" : "remaining")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ink2)
                } else {
                    Text(TimeDisplay.time(focus.start, format))
                        .font(.varsity(size: 22))
                    Text("first bell")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ink2)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: 108, alignment: .trailing)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private func dayRows(_ blocks: [ResolvedBlock], schedule: WidgetScheduleEntry,
                         compact: Bool, spacious: Bool = false) -> some View {
        VStack(spacing: 2) {
            ForEach(blocks) { block in
                let focused = schedule.focus?.id == block.id
                let completed = block.end <= schedule.date
                let patchInk = fullColor ? Self.patchInk(on: ground) : Color.primary
                HStack(spacing: compact ? 4 : 7) {
                    Group {
                        if completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(ink2)
                        } else if focused {
                            Capsule()
                                .fill(patchInk)
                                .frame(width: 3, height: 14)
                                .widgetAccentable()
                        } else {
                            Color.clear.frame(height: 1)
                        }
                    }
                    .frame(width: 7)
                    .accessibilityHidden(true)

                    periodName(block)
                        .font(.system(size: compact ? 11 : 13, weight: focused ? .semibold : .medium))
                        .foregroundStyle(focused ? patchInk : (completed ? ink2 : ink))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !compact, let room = block.room {
                        Text(room)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(focused ? patchInk : ink2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .background((focused ? patchInk : ink).opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                            .frame(maxWidth: 43, alignment: .trailing)
                    }
                    rowTime(block, compact: compact)
                        .font(.system(size: compact ? 10 : 11, weight: focused ? .medium : .regular))
                        .monospacedDigit()
                        .foregroundStyle(focused ? patchInk : ink2)
                }
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(minHeight: spacious ? 24 : nil, maxHeight: spacious ? .infinity : nil)
                .background(focused ? Self.patchFill(on: ground, fullColor: fullColor) : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(focused ? (block.start > schedule.date ? "Up next. " : "Current. ") : completed ? "Completed. " : "")\(block.displayName). \(details(block))")
                .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: !spacious)
    }

    /// The current block in the large widget is sewn on like Home's patch.
    private static func patchFill(on ground: JacketGround, fullColor: Bool) -> Color {
        guard fullColor else { return Color.primary.opacity(0.12) }
        switch ground {
        case .field: return Jacket.chenille
        case .gold: return Jacket.field
        case .lining: return Jacket.accent
        }
    }

    private static func patchInk(on ground: JacketGround) -> Color {
        switch ground {
        case .field: return Jacket.field
        case .gold: return Jacket.chenille
        case .lining: return Jacket.onAccent
        }
    }

    private func rowTime(_ block: ResolvedBlock, compact: Bool) -> some View {
        HStack(spacing: 3) {
            Text(TimeDisplay.time(block.start, format, includesMeridiem: false))
                .frame(maxWidth: .infinity, alignment: .trailing)
            if !compact {
                Text("–")
                Text(TimeDisplay.time(block.end, format, includesMeridiem: false))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        // Reserve equal bell-time columns, including for single-digit hours.
        .frame(width: compact ? 36 : 88)
    }

    private func periodName(_ block: ResolvedBlock) -> some View {
        WidgetPeriodName(
            emoji: block.role == .classPeriod ? ScheduleStyle.emoji(for: block, config: entry.config) : nil,
            name: block.displayName
        )
    }

    private func details(_ block: ResolvedBlock) -> String {
        let range = TimeDisplay.range(block.start, block.end, format)
        return block.room.map { "Room \($0) · \(range)" } ?? range
    }

    @ViewBuilder
    private func resting(_ schedule: WidgetScheduleEntry) -> some View {
        if rectangular || typeSize.isAccessibilitySize {
            compactResting(schedule)
        } else {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(status(schedule))
                            .font(.title3.bold())
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !medium { patriot(height: 34) }
                    }
                    if case .unknownSchedule(let name) = schedule.state {
                        Text(name).font(.caption).foregroundStyle(ink2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let next = schedule.nextSchoolDay, let start = next.firstBell {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Back to school")
                                .widgetLabel()
                                .foregroundStyle(ink2)
                            Text(TimeDisplay.shortDayLabel(next.day))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(next.scheduleLabel)
                                .font(.caption2)
                                .foregroundStyle(ink2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(TimeDisplay.time(start, format))
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(fullColor ? Jacket.twill : Color.primary)
                                .frame(width: 3)
                                .widgetAccentable()
                        }
                    } else {
                        Text("No upcoming school day available")
                            .font(.caption).foregroundStyle(ink2).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if medium { patriot(height: 110) }
            }
        }
    }

    // A SwiftUI frame only changes layout; it leaves the full 1307 × 1687
    // bitmap in the widget archive. Prepare a bounded image once for all
    // timeline entries, sized for the largest (110 pt) logo at 3× scale.
    private static let patriotThumbnail = UIImage(named: "Patriot")?
        .preparingThumbnail(of: CGSize(width: 330, height: 330))

    @ViewBuilder
    private func patriot(height: CGFloat) -> some View {
        if let thumbnail = Self.patriotThumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .widgetAccentedRenderingMode(.desaturated)
                .scaledToFit()
                .frame(width: height * 0.78, height: height)
                .accessibilityHidden(true)
        }
    }

    private func compactResting(_ schedule: WidgetScheduleEntry) -> some View {
        VStack(alignment: .leading, spacing: rectangular ? 2 : 8) {
            Text(status(schedule))
                .font(rectangular ? .headline : .title3.bold())
                .lineLimit(rectangular ? 1 : 2)
                .minimumScaleFactor(0.8)
            if case .unknownSchedule(let name) = schedule.state {
                Text(name).font(.caption).foregroundStyle(ink2).lineLimit(1)
            }
            if let next = schedule.nextSchoolDay, let start = next.firstBell {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TimeDisplay.shortDayLabel(next.day))
                        .font(rectangular ? .caption : .subheadline.weight(.semibold))
                    Text("\(next.scheduleLabel) · \(TimeDisplay.time(start, format))")
                        .font(.caption).foregroundStyle(ink2)
                        .lineLimit(rectangular ? 1 : 2)
                }
            } else {
                Text("No upcoming school day available")
                    .font(.caption).foregroundStyle(ink2).lineLimit(2)
            }
        }
    }

    private func status(_ schedule: WidgetScheduleEntry) -> String {
        switch schedule.state {
        case .afterSchool: return schedule.isFinished ? "School finished" : "Next school day"
        case .unknownSchedule: return "Schedule unavailable"
        case .asynchronous: return "Asynchronous learning"
        default: return schedule.timeline.scheduleLabel
        }
    }
}

private struct WidgetPeriodName: View {
    /// The student's class emoji; nil for lunch, free and other blocks.
    let emoji: String?
    let name: String

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.font) private var font
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.displayScale) private var displayScale

    private struct EmojiImageKey: Hashable {
        let emoji: String
        let font: Font?
        let typeSize: DynamicTypeSize
        let legibilityWeight: LegibilityWeight?
        let displayScale: CGFloat
    }

    @MainActor private static var emojiImages: [EmojiImageKey: UIImage] = [:]

    var body: some View {
        if let emoji {
            withEmoji(emoji)
        } else {
            Text(name)
        }
    }

    @ViewBuilder
    private func withEmoji(_ emoji: String) -> some View {
        if renderingMode == .accented, let image = emojiImage(emoji) {
            // Both views use the same font and line height, so their first
            // lines align even when the name wraps onto additional lines.
            HStack(alignment: .top, spacing: 0) {
                Image(uiImage: image)
                    .widgetAccentedRenderingMode(.desaturated)
                Text(" \(name)")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(emoji) \(name)"))
        } else {
            Text("\(emoji) \(name)")
        }
    }

    private func emojiImage(_ emoji: String) -> UIImage? {
        let key = EmojiImageKey(emoji: emoji, font: font, typeSize: typeSize,
                                legibilityWeight: legibilityWeight, displayScale: displayScale)
        if let image = Self.emojiImages[key] { return image }
        // Accented mode treats text (including emoji) as a monochrome mask.
        // WidgetKit's image-only desaturated mode preserves luminance detail
        // in the system tint. Rasterize just the glyph at its displayed size,
        // keeping widget archives small.
        let renderer = ImageRenderer(content:
            Text(emoji)
                .font(font)
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.legibilityWeight, legibilityWeight)
                .fixedSize()
        )
        renderer.scale = displayScale
        guard let image = renderer.uiImage else { return nil }
        // Reuse glyphs across timeline entries, with a bound for long-lived
        // preview processes that cycle through fonts and accessibility sizes.
        if Self.emojiImages.count >= 64 { Self.emojiImages.removeAll(keepingCapacity: true) }
        Self.emojiImages[key] = image
        return image
    }
}

#Preview("Small · long name", as: .systemSmall) {
    ScheduleWidget()
} timeline: {
    ScheduleProvider.example(at: HourMinute(hour: 9, minute: 0), longName: true)
    ScheduleProvider.example(at: HourMinute(hour: 9, minute: 21), room: nil)
    ScheduleProvider.example(at: HourMinute(hour: 8, minute: 15))
    ScheduleProvider.example(at: HourMinute(hour: 15, minute: 25))
    ScheduleProvider.example(at: HourMinute(hour: 15, minute: 30))
}

#Preview("Medium", as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    ScheduleProvider.example
    ScheduleProvider.example(at: HourMinute(hour: 9, minute: 21))
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    ScheduleWidget()
} timeline: {
    ScheduleProvider.example(at: HourMinute(hour: 9, minute: 0), longName: true, room: nil)
    ScheduleProvider.example(at: HourMinute(hour: 8, minute: 15))
}

#Preview("Lock Screen · circular", as: .accessoryCircular) {
    ScheduleWidget()
} timeline: {
    ScheduleProvider.example(at: HourMinute(hour: 9, minute: 0))
    ScheduleProvider.example(at: HourMinute(hour: 9, minute: 21))
    ScheduleProvider.example(at: HourMinute(hour: 8, minute: 15))
    ScheduleProvider.example(at: HourMinute(hour: 7, minute: 0))
    ScheduleProvider.example(at: HourMinute(hour: 15, minute: 30))
    ScheduleProvider.weekendExample
}

// PreviewProvider supports explicit WidgetPreviewContext for layout variants.
struct ScheduleLayoutPreviews: PreviewProvider {
    static var previews: some View {
        ForEach([WidgetFamily.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular],
                id: \.self) { family in
            ScheduleWidgetView(entry: ScheduleProvider.example(at: HourMinute(hour: 9, minute: 0), longName: true, room: nil))
                .containerBackground(.background, for: .widget)
                .environment(\.dynamicTypeSize, .accessibility1)
                .preferredColorScheme(.dark)
                .previewContext(WidgetPreviewContext(family: family))
                .previewDisplayName("Large text · dark · \(family)")
        }
    }
}

#Preview("Small · weekend", as: .systemSmall) {
    ScheduleWidget()
} timeline: {
    ScheduleProvider.weekendExample
}

#Preview("Medium · weekend", as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    ScheduleProvider.weekendExample
}

/// The widget wears the same grounds as Home: green while a block is on,
/// gold between bells (and in the last hour before school), the lining when
/// nothing is happening.
struct ScheduleWidgetBackground: View {
    let entry: ScheduleWidgetEntry
    @Environment(\.widgetFamily) private var family

    static func ground(for entry: ScheduleWidgetEntry) -> JacketGround {
        guard let schedule = entry.schedule else { return .lining }
        switch schedule.state {
        case .inBlock: return .field
        case .passing: return .gold
        case .beforeSchool: return schedule.isLeadIn ? .gold : .lining
        default: return .lining
        }
    }

    var body: some View {
        if family == .accessoryRectangular || family == .accessoryCircular {
            Rectangle().fill(.background)
        } else {
            Self.ground(for: entry).background
        }
    }
}

/// The lining, for widgets with nothing on right now.
struct RestingWidgetBackground: View {
    var body: some View {
        Jacket.lining
    }
}

extension View {
    /// A widget-sized jacket label: Expanded Bold caps.
    func widgetLabel() -> some View {
        font(.system(size: 11, weight: .bold).width(.expanded))
            .textCase(.uppercase)
            .tracking(0.8)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

/// A running stitch standing on end: the divider between a medium widget's columns.
private struct VerticalStitch: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0.75, y: 0))
                path.addLine(to: CGPoint(x: 0.75, y: proxy.size.height))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3.5]))
        }
        .frame(width: 1.5)
        .accessibilityHidden(true)
    }
}

#Preview("Large · full day", as: .systemLarge) {
    ScheduleWidget()
} timeline: {
    ScheduleProvider.example(at: HourMinute(hour: 8, minute: 0))
    ScheduleProvider.example(at: HourMinute(hour: 8, minute: 15))
    ScheduleProvider.example(at: HourMinute(hour: 9, minute: 0), longName: true)
    ScheduleProvider.example(at: HourMinute(hour: 9, minute: 21), room: nil)
    ScheduleProvider.example(at: HourMinute(hour: 15, minute: 25))
    ScheduleProvider.example(at: HourMinute(hour: 15, minute: 30))
    ScheduleProvider.weekendExample
}

#Preview("Large · weekend next school day", as: .systemLarge) {
    ScheduleWidget()
} timeline: {
    ScheduleProvider.weekendExample
    ScheduleProvider.weekendExample(family: .standard, dense: true)
    ScheduleProvider.weekendExample(family: .lateArrival)
}

#Preview("Large · special and split schedules", as: .systemLarge) {
    ScheduleWidget()
} timeline: {
    ScheduleProvider.fullDayExample()
    ScheduleProvider.fullDayExample(dense: true)
    ScheduleProvider.fullDayExample(family: .lateArrival)
    ScheduleProvider.fullDayExample(family: .pmAssembly)
    ScheduleProvider.fullDayExample(family: .earlyDismissal)
}

struct LargeSchedulePrivacyPreview: PreviewProvider {
    static var previews: some View {
        ScheduleWidgetView(entry: ScheduleProvider.fullDayExample(dense: true))
            .redacted(reason: .privacy)
            .containerBackground(.background, for: .widget)
            .previewContext(WidgetPreviewContext(family: .systemLarge))
            .previewDisplayName("Large · privacy")
    }
}

#Preview("Large · custom classes", as: .systemLarge) {
    ScheduleWidget()
} timeline: {
    ScheduleProvider.customClassesExample
}
