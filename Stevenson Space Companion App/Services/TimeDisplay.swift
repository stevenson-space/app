import Foundation
import ScheduleKit

/// All user-facing time formatting. Bell times always display in the school's
/// timezone — a student checking from out of town sees Stevenson's clock.
enum TimeDisplay {
    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = SchoolTime.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    private static let twelveHour = makeFormatter("h:mm a")
    private static let twelveHourShort = makeFormatter("h:mm")
    private static let twentyFourHour = makeFormatter("H:mm")
    private static let weekdayMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        formatter.timeZone = SchoolTime.timeZone
        return formatter
    }()
    private static let shortWeekdayMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        formatter.timeZone = SchoolTime.timeZone
        return formatter
    }()

    static var systemUses24Hour: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?
            .contains("H") ?? false
    }

    static func uses24Hour(_ pref: TimeFormatPref) -> Bool {
        switch pref {
        case .twentyFourHour: return true
        case .twelveHour: return false
        case .system: return systemUses24Hour
        }
    }

    /// "2:33 PM" / "14:33"
    static func time(_ date: Date, _ pref: TimeFormatPref) -> String {
        uses24Hour(pref) ? twentyFourHour.string(from: date) : twelveHour.string(from: date)
    }

    /// "8:30 – 9:21" (meridiem dropped in ranges; bell times are unambiguous)
    static func range(_ start: Date, _ end: Date, _ pref: TimeFormatPref) -> String {
        if uses24Hour(pref) {
            return "\(twentyFourHour.string(from: start)) – \(twentyFourHour.string(from: end))"
        }
        return "\(twelveHourShort.string(from: start)) – \(twelveHourShort.string(from: end))"
    }

    /// "In 14h 9m" / "In 12m" / "Now" — the upcoming-block chip.
    static func untilChip(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "In \(hours)h \(minutes)m" }
        if minutes > 0 { return "In \(minutes)m" }
        return "Now"
    }

    /// "42:07" under an hour, "1:02:33" above.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Spoken form for VoiceOver: "42 minutes", "1 hour 2 minutes".
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr"
        }
        if minutes > 0 { return "\(minutes) min" }
        return "under a minute"
    }

    /// "Today" / "Tomorrow" / "Monday, Aug 24"
    static func dayLabel(_ day: DayKey, relativeTo today: DayKey) -> String {
        if day == today { return "Today" }
        if day == today.advanced(by: 1) { return "Tomorrow" }
        guard let date = day.date() else { return day.description }
        return weekdayMonthDay.string(from: date)
    }

    /// "Wed, Aug 12"
    static func shortDayLabel(_ day: DayKey) -> String {
        guard let date = day.date() else { return day.description }
        return shortWeekdayMonthDay.string(from: date)
    }
}
