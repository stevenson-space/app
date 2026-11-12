import Foundation
import Testing
@testable import ScheduleKit

@Suite struct TimeDisplayTests {
    /// A student whose iPhone is set to the Islamic calendar still sees the
    /// school's date: Aug 12, 2026 falls in Safar there.
    @Test func dayLabelsUseTheSchoolCalendarWhateverTheDeviceUses() throws {
        let formatter = TimeDisplay.makeDayFormatter(
            "MMM d", locale: Locale(identifier: "en_US@calendar=islamic"))
        let date = try #require(day(2026, 8, 12).date())
        #expect(formatter.string(from: date) == "Aug 12")
    }

    /// 11 PM in Chicago is already the next day in UTC; labels name the
    /// school's day.
    @Test func dayLabelsNameTheSchoolDay() throws {
        let formatter = TimeDisplay.makeDayFormatter(
            "EEE, MMM d", locale: Locale(identifier: "en_US_POSIX"))
        let date = try #require(day(2026, 8, 12).date(at: HourMinute(hour: 23, minute: 0)))
        #expect(formatter.string(from: date) == "Wed, Aug 12")
    }
}
