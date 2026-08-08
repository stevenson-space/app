import Testing
import Foundation
@testable import ScheduleKit

@Suite struct SchoolYearTests {
    @Test func yearBounds() {
        #expect(SchoolYearCatalog.year(containing: DayKey(year: 2026, month: 9, day: 15)) != nil)
        #expect(SchoolYearCatalog.year(containing: DayKey(year: 2026, month: 8, day: 12)) != nil)
        #expect(SchoolYearCatalog.year(containing: DayKey(year: 2027, month: 5, day: 26)) != nil)
        #expect(SchoolYearCatalog.year(containing: DayKey(year: 2026, month: 7, day: 30)) == nil)
        #expect(SchoolYearCatalog.year(containing: DayKey(year: 2027, month: 5, day: 27)) == nil)
    }

    @Test func breaksAreInsideTheYear() throws {
        let year = SchoolYearCatalog.year2026_27
        let winterDay = DayKey(year: 2026, month: 12, day: 25)
        let springDay = DayKey(year: 2027, month: 3, day: 24)
        #expect(year.breakContaining(winterDay)?.label == "Winter Break")
        #expect(year.breakContaining(springDay)?.label == "Spring Break")
        #expect(year.breakContaining(DayKey(year: 2027, month: 1, day: 6))?.label == "Winter Break")
        #expect(year.breakContaining(DayKey(year: 2027, month: 1, day: 7)) == nil)
        #expect(year.breakContaining(DayKey(year: 2026, month: 10, day: 1)) == nil)
    }

    @Test func orientationDayIsLabeled() {
        let year = SchoolYearCatalog.year2026_27
        #expect(year.labeledDays[DayKey(year: 2026, month: 8, day: 12)] == "Freshman Orientation")
    }

    @Test func nextYearStart() {
        #expect(SchoolYearCatalog.nextYearStart(after: DayKey(year: 2026, month: 7, day: 30))
                == DayKey(year: 2026, month: 8, day: 12))
        #expect(SchoolYearCatalog.nextYearStart(after: DayKey(year: 2026, month: 8, day: 12)) == nil)
    }
}

@Suite struct DayKeyTests {
    @Test func weekdayAndWeekend() {
        // Aug 12 2026 is a Wednesday; Aug 15 2026 is a Saturday.
        #expect(DayKey(year: 2026, month: 8, day: 12).weekday() == 4)
        #expect(!DayKey(year: 2026, month: 8, day: 12).isWeekend)
        #expect(DayKey(year: 2026, month: 8, day: 15).isWeekend)
        #expect(DayKey(year: 2026, month: 8, day: 16).isWeekend) // Sunday
    }

    @Test func advancingCrossesDSTSafely() {
        // Fall-back happens overnight into Nov 1 2026.
        let halloween = DayKey(year: 2026, month: 10, day: 31)
        #expect(halloween.advanced(by: 1) == DayKey(year: 2026, month: 11, day: 1))
        #expect(halloween.advanced(by: 2) == DayKey(year: 2026, month: 11, day: 2))
    }

    @Test func wallClockTimesSurviveDST() throws {
        // 8:30 AM the day before and the day after fall-back are 25 hours apart;
        // around spring-forward (Mar 14 2027) they are 23 hours apart.
        let time = HourMinute(hour: 8, minute: 30)
        let beforeFall = try #require(DayKey(year: 2026, month: 10, day: 31).date(at: time))
        let afterFall = try #require(DayKey(year: 2026, month: 11, day: 1).date(at: time))
        #expect(afterFall.timeIntervalSince(beforeFall) == 25 * 3600)

        let beforeSpring = try #require(DayKey(year: 2027, month: 3, day: 13).date(at: time))
        let afterSpring = try #require(DayKey(year: 2027, month: 3, day: 14).date(at: time))
        #expect(afterSpring.timeIntervalSince(beforeSpring) == 23 * 3600)
    }

    @Test func invalidDatesDetected() {
        #expect(!DayKey(year: 2027, month: 2, day: 30).isValid)
        #expect(DayKey(year: 2028, month: 2, day: 29).isValid) // leap year
        #expect(!DayKey(year: 2027, month: 2, day: 29).isValid)
    }

    @Test func ordering() {
        #expect(DayKey(year: 2026, month: 12, day: 31) < DayKey(year: 2027, month: 1, day: 1))
        #expect(DayKey(year: 2026, month: 8, day: 12) < DayKey(year: 2026, month: 9, day: 1))
    }
}
