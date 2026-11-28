import ScheduleKit
import SwiftUI

/// The one-line Lock Screen slot beside the date. The system keeps only the
/// text and one symbol and draws them in its own font, so each state lists
/// shorter versions, longest first, for `ViewThatFits` to fall back on.
///
/// It names the next bell's time instead of counting down: on the Lock Screen
/// this slot froze both timer styles at the minute they were drawn.
struct InlineScheduleView: View {
    let entry: ScheduleWidgetEntry

    private var format: TimeFormatPref { entry.config.timeFormat }

    var body: some View {
        if let schedule = entry.schedule {
            if case .unknownSchedule = schedule.state {
                fitting("calendar.badge.exclamationmark", "Schedule unavailable", "Unavailable")
            } else if let name = schedule.focus?.displayName, case .inBlock(let current, _) = schedule.state {
                upcomingBell("bell", at: current.end) { time in
                    ["\(name) ends at \(time)", "Ends at \(time)", time]
                }
            } else if let name = schedule.focus?.displayName, case .passing(_, let next, _) = schedule.state {
                upcomingBell("figure.walk", at: next.start) { time in
                    ["\(name) starts at \(time)", "Passing until \(time)", time]
                }
            } else if let bell = schedule.nextFirstBell {
                firstBell(bell, today: schedule.timeline.day)
            } else {
                fitting("calendar", "Next school day not posted yet", "Next school day TBA", "School day TBA")
            }
        } else {
            fitting("calendar.badge.exclamationmark", "No schedule yet", "No schedule")
        }
    }

    /// A bell later today, without AM or PM like the circular widget, since
    /// the clock sits right below. VoiceOver still hears the full time.
    private func upcomingBell(_ symbol: String, at date: Date, texts: (String) -> [String]) -> some View {
        fitting(symbol, texts(TimeDisplay.time(date, format, includesMeridiem: false)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(texts(TimeDisplay.time(date, format))[0])
    }

    /// "First bell 8:30 AM" today or "Mon, Nov 30 · 8:30 AM" for a later day,
    /// then "Today 8:30 AM" or "Mon 8:30 AM", then without AM or PM.
    private func firstBell(_ bell: (day: DayKey, time: Date), today: DayKey) -> some View {
        let time = TimeDisplay.time(bell.time, format)
        let day = TimeDisplay.dayLabel(bell.day, relativeTo: today, compact: true)
        return fitting("bell",
                       bell.day == today ? "First bell \(time)" : "\(TimeDisplay.shortDayLabel(bell.day)) · \(time)",
                       "\(day) \(time)",
                       "\(day) \(TimeDisplay.time(bell.time, format, includesMeridiem: false))")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("First bell \(TimeDisplay.dayLabel(bell.day, relativeTo: today)), \(time)")
    }

    private func fitting(_ symbol: String, _ texts: String...) -> some View {
        fitting(symbol, texts)
    }

    private func fitting(_ symbol: String, _ texts: [String]) -> some View {
        // Only width decides: a tall symbol mustn't push every version out.
        ViewThatFits(in: .horizontal) {
            ForEach(texts.indices, id: \.self) { index in
                Label(texts[index], systemImage: symbol)
            }
        }
    }
}
