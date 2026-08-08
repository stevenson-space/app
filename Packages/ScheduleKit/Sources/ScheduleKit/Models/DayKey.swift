import Foundation

/// A calendar date in the school's timezone. All persistence and map keys use
/// DayKey — never raw `Date` — so keys are timezone-proof and DST-proof.
public struct DayKey: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = SchoolTime.calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1, month: components.month ?? 1, day: components.day ?? 1)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Materializes a concrete instant for this date at the given wall-clock time.
    public func date(at time: HourMinute = HourMinute(hour: 0, minute: 0),
                     calendar: Calendar = SchoolTime.calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components)
    }

    /// 1 = Sunday … 7 = Saturday.
    public func weekday(calendar: Calendar = SchoolTime.calendar) -> Int? {
        guard let date = date(calendar: calendar) else { return nil }
        return calendar.component(.weekday, from: date)
    }

    public var isWeekend: Bool {
        guard let weekday = weekday() else { return false }
        return weekday == 1 || weekday == 7
    }

    /// Calendar-correct day stepping (safe across DST transitions).
    public func advanced(by days: Int, calendar: Calendar = SchoolTime.calendar) -> DayKey {
        guard let base = date(calendar: calendar),
              let shifted = calendar.date(byAdding: .day, value: days, to: base) else { return self }
        return DayKey(date: shifted, calendar: calendar)
    }

    /// `Calendar.date(from:)` is lenient (rolls Feb 30 into March); a round-trip
    /// detects genuinely nonexistent dates.
    public var isValid: Bool {
        guard let date = date() else { return false }
        return DayKey(date: date) == self
    }
}
