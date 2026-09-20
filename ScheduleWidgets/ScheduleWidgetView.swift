import ScheduleKit
import SwiftUI
import UIKit
import WidgetKit

struct ScheduleWidgetView: View {
    let entry: ScheduleWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize = 42

    private var rectangular: Bool { family == .accessoryRectangular }
    private var medium: Bool { family == .systemMedium }
    private var format: TimeFormatPref { entry.config.timeFormat }

    var body: some View {
        Group {
            if let schedule = entry.schedule {
                if let focus = schedule.focus {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityHint("Opens today’s schedule in Stevenson Space")
    }

    private func accent(_ schedule: WidgetScheduleEntry, focus: ResolvedBlock) -> Color {
        guard renderingMode == .fullColor, contrast != .increased else { return .primary }
        if case .passing = schedule.state { return .orange }
        return ScheduleStyle.tint(for: focus.role)
    }

    private func caption(_ schedule: WidgetScheduleEntry) -> String {
        switch schedule.state {
        case .beforeSchool: return schedule.isLeadIn ? "School starts in" : schedule.timeline.scheduleLabel
        case .passing: return "Passing · starts in"
        default: return "Period ends in"
        }
    }

    private func active(_ schedule: WidgetScheduleEntry, focus: ResolvedBlock) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: rectangular || typeSize.isAccessibilitySize ? 1 : 5) {
                Text(caption(schedule))
                    .font(rectangular ? .caption2 : .caption.weight(.semibold))
                    .foregroundStyle(accent(schedule, focus: focus))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let interval = entry.countdownInterval {
                    Text(timerInterval: interval, countsDown: true)
                        .font(rectangular ? .title2.weight(.bold) : .system(size: min(timerSize, 54), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.identity)
                } else {
                    Text(TimeDisplay.time(focus.start, format))
                        .font(rectangular ? .title3.bold() : .title.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                if schedule.isLeadIn, !medium, !rectangular, !typeSize.isAccessibilitySize {
                    Text(schedule.timeline.scheduleLabel)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .accessibilityElement(children: .contain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if medium {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if let next = schedule.upcoming {
                        Text("UP NEXT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        periodName(next).font(.subheadline.weight(.semibold)).lineLimit(3)
                        if let room = next.room { Text("Room \(room)").font(.caption).lineLimit(1) }
                        Text(TimeDisplay.time(next.start, format)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("LAST PERIOD").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text("School finishes at \(TimeDisplay.time(focus.end, format))")
                            .font(.subheadline).lineLimit(3)
                    }
                    Text(schedule.timeline.scheduleLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func periodName(_ block: ResolvedBlock) -> some View {
        WidgetPeriodName(
            emoji: ScheduleStyle.emoji(for: block, config: entry.config),
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
                        Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let next = schedule.nextSchoolDay, let start = next.firstBell {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("BACK TO SCHOOL")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(.secondary)
                            Text(TimeDisplay.shortDayLabel(next.day))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(next.scheduleLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(TimeDisplay.time(start, format))
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(renderingMode == .fullColor && contrast != .increased
                                      ? Color(red: 0.78, green: 0.60, blue: 0.16) : Color.primary)
                                .frame(width: 3)
                                .widgetAccentable()
                        }
                    } else {
                        Text("No upcoming school day available")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
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
                Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let next = schedule.nextSchoolDay, let start = next.firstBell {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TimeDisplay.shortDayLabel(next.day))
                        .font(rectangular ? .caption : .subheadline.weight(.semibold))
                    Text("\(next.scheduleLabel) · \(TimeDisplay.time(start, format))")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(rectangular ? 1 : 2)
                }
            } else {
                Text("No upcoming school day available")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
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
    let emoji: String
    let name: String

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.font) private var font
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if renderingMode == .accented, let image = emojiImage {
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

    private var emojiImage: UIImage? {
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
        return renderer.uiImage
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

// PreviewProvider supports explicit WidgetPreviewContext for layout variants.
struct ScheduleLayoutPreviews: PreviewProvider {
    static var previews: some View {
        ForEach([WidgetFamily.systemSmall, .systemMedium, .accessoryRectangular], id: \.self) { family in
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

struct ScheduleWidgetBackground: View {
    let entry: ScheduleWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let schedule = entry.schedule, schedule.focus == nil, family != .accessoryRectangular {
            LinearGradient(
                colors: [Color.primary.opacity(0.02), Color.green.opacity(0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .background(.background)
        } else {
            Rectangle().fill(.background)
        }
    }
}
