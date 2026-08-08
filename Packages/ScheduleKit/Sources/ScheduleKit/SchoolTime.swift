import Foundation

/// All schedule math happens in the school's timezone, regardless of where the
/// device is. Dates are always materialized from per-day wall-clock components —
/// never by adding fixed intervals across days — so DST transitions cannot shift
/// bell times.
public enum SchoolTime {
    public static let timeZone = TimeZone(identifier: "America/Chicago")!

    /// A Gregorian calendar pinned to the school's timezone.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()
}
