import ScheduleKit
import SwiftUI
import WidgetKit

/// The smallest Lock Screen size: minutes and seconds left in the current
/// period, passing time, or lead-in. Otherwise it names the next first bell.
struct CircularScheduleView: View {
    let entry: ScheduleWidgetEntry

    private var format: TimeFormatPref { entry.config.timeFormat }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            content
                // Keep text clear of the circle's edge.
                .padding(.horizontal, 6)
        }
        // A fixed circle has no room to grow; the timer is already its largest text.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    @ViewBuilder
    private var content: some View {
        if let schedule = entry.schedule {
            if case .unknownSchedule = schedule.state {
                symbol("calendar.badge.exclamationmark", label: "Schedule unavailable")
            } else if let interval = entry.countdownInterval {
                labeled(caption(schedule)) {
                    // Minutes only, even past an hour, so the text stays short.
                    Text(timerInterval: interval, pauseTime: entry.countdownPauseTime,
                         countsDown: true, showsHours: false)
                        // Timer text fills the available width; center it there.
                        .multilineTextAlignment(.center)
                        .contentTransition(.identity)
                }
            } else if let bell = nextFirstBell(schedule) {
                labeled(TimeDisplay.shortWeekdayLabel(bell.day).uppercased()) {
                    Text(TimeDisplay.time(bell.time, format, includesMeridiem: false))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("First bell \(TimeDisplay.shortDayLabel(bell.day)), \(TimeDisplay.time(bell.time, format))")
            } else {
                symbol("calendar", label: "No upcoming school day")
            }
        } else {
            symbol("calendar.badge.exclamationmark", label: "Open Stevenson Space")
        }
    }

    private func labeled(_ caption: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: 0) {
            Text(caption)
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            value()
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ name: String, label: String) -> some View {
        Image(systemName: name)
            .font(.title2)
            .accessibilityLabel(label)
    }

    private func caption(_ schedule: WidgetScheduleEntry) -> String {
        switch schedule.state {
        case .beforeSchool: return "STARTS IN"
        case .passing: return "PASSING"
        default: return "ENDS IN"
        }
    }

    /// Today's first bell before school, or the next school day's afterward.
    private func nextFirstBell(_ schedule: WidgetScheduleEntry) -> (day: DayKey, time: Date)? {
        if case .beforeSchool = schedule.state, let first = schedule.timeline.firstBell {
            return (schedule.timeline.day, first)
        }
        guard let next = schedule.nextSchoolDay, let first = next.firstBell else { return nil }
        return (next.day, first)
    }
}
