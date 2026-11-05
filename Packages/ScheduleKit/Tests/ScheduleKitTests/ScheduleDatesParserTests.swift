import Testing
import Foundation
@testable import ScheduleKit

@Suite struct ScheduleDatesParserTests {
    @Test func parsesRealSnapshot() throws {
        let map = try ScheduleDatesParser.parse(TestSupport.fixture("schedule-dates-snapshot"))
        #expect(!map.entries.isEmpty)
        #expect(map.warnings.isEmpty)

        // Known entries from the 2025–26 file.
        let lateArrival = try #require(map.match(day(2025, 8, 21)))
        #expect(lateArrival.family == .bell(.lateArrival))

        let finals = try #require(map.match(day(2025, 12, 19)))
        #expect(finals.family == .bell(.earlyDismissal))
        #expect(finals.span == DateSpan(start: day(2025, 12, 18), end: day(2025, 12, 19)))

        let coverage = try #require(map.coverage)
        #expect(coverage.start == day(2025, 8, 19))
        #expect(coverage.end == day(2026, 8, 14))

        // A weekday never listed resolves to nothing (Standard is by-design absence).
        #expect(map.match(day(2025, 9, 3)) == nil)
    }

    @Test func datesWithoutLeadingZerosAndRanges() throws {
        let map = try TestSupport.map(
            #"{"No School": ["9/1/2026", "11/25/2026-11/27/2026"]}"#)
        #expect(map.match(day(2026, 9, 1))?.family == .noSchool)
        #expect(map.match(day(2026, 11, 26))?.family == .noSchool)
        #expect(map.match(day(2026, 11, 27))?.family == .noSchool)
        #expect(map.match(day(2026, 11, 28)) == nil)
    }

    @Test func weekendsInsideRangesAreLeftToTheCalendar() throws {
        let map = try TestSupport.map(
            #"{"Late Arrival": ["10/9/2026-10/12/2026", "10/17/2026"], "No School": ["11/25/2026-11/30/2026"]}"#)
        // The Friday and Monday ends of the range match…
        #expect(map.match(day(2026, 10, 9))?.family == .bell(.lateArrival))
        #expect(map.match(day(2026, 10, 12))?.family == .bell(.lateArrival))
        // …the weekend between them does not…
        #expect(map.match(day(2026, 10, 10)) == nil)
        #expect(map.match(day(2026, 10, 11)) == nil)
        // …a weekend listed as its own date still does…
        #expect(map.match(day(2026, 10, 17))?.family == .bell(.lateArrival))
        // …and a No School range keeps its weekend.
        #expect(map.match(day(2026, 11, 28))?.family == .noSchool)
    }

    @Test func weekendListedOnItsOwnBeatsASurroundingNoSchoolRange() throws {
        let map = try TestSupport.map(
            #"{"Late Arrival": ["11/28/2026"], "No School": ["11/25/2026-11/30/2026"]}"#)
        // Saturday 11/28 is listed on its own, so it wins over the range…
        let saturday = try #require(map.match(day(2026, 11, 28)))
        #expect(saturday.family == .bell(.lateArrival))
        #expect(saturday.hadConflict)
        // …while the rest of the range, weekend and weekday alike, is No School.
        #expect(map.match(day(2026, 11, 29))?.family == .noSchool)
        #expect(map.match(day(2026, 11, 30))?.family == .noSchool)
    }

    @Test func keyRegistryAndAliases() {
        #expect(ScheduleDatesParser.family(forKey: "Late Arrival") == .bell(.lateArrival))
        #expect(ScheduleDatesParser.family(forKey: "Activity Period") == .bell(.activityPeriod))
        #expect(ScheduleDatesParser.family(forKey: "PM Assembly") == .bell(.pmAssembly))
        #expect(ScheduleDatesParser.family(forKey: "Early Dismissal") == .bell(.earlyDismissal))
        #expect(ScheduleDatesParser.family(forKey: "No School") == .noSchool)
        #expect(ScheduleDatesParser.family(forKey: "Odyssey") == .bell(.odyssey))
        #expect(ScheduleDatesParser.family(forKey: "Summer School") == .bell(.summer))

        // Canonical async key plus tolerated variants, case-insensitive.
        #expect(ScheduleDatesParser.family(forKey: "Asynchronous") == .asynchronous)
        #expect(ScheduleDatesParser.family(forKey: " ASYNC ") == .asynchronous)
        #expect(ScheduleDatesParser.family(forKey: "E-Learning") == .asynchronous)
        #expect(ScheduleDatesParser.family(forKey: "Asynchronous E-Learning Day") == .asynchronous)

        #expect(ScheduleDatesParser.family(forKey: "Wacky Hat Day")
                == .unknown(rawKey: "Wacky Hat Day"))
    }

    @Test func unknownKeysArePreservedNotDropped() throws {
        let map = try TestSupport.map(#"{"Wacky Hat Day": ["10/6/2026"]}"#)
        let match = try #require(map.match(day(2026, 10, 6)))
        #expect(match.family == .unknown(rawKey: "Wacky Hat Day"))
    }

    @Test func malformedEntriesSkippedWithWarnings() throws {
        let map = try TestSupport.map(
            #"{"Late Arrival": ["9/18/2026", "not a date", "2/30/2027", "9/2/2026-9/1/2026"]}"#)
        #expect(map.entries.count == 1)
        #expect(map.warnings.count == 3)
        #expect(map.match(day(2026, 9, 18))?.family == .bell(.lateArrival))
    }

    @Test func nonConformingFilesFailWholesale() {
        #expect(throws: ParserError.notAnObject) {
            _ = try ScheduleDatesParser.parse(Data("[1,2,3]".utf8))
        }
        #expect(throws: ParserError.notAnObject) {
            _ = try ScheduleDatesParser.parse(Data("garbage".utf8))
        }
        #expect(throws: ParserError.noValidEntries) {
            _ = try ScheduleDatesParser.parse(Data(#"{"Late Arrival": ["nope"]}"#.utf8))
        }
        #expect(throws: ParserError.self) {
            _ = try ScheduleDatesParser.parse(Data(repeating: 0x20, count: ScheduleDatesParser.maxBytes + 1))
        }
    }

    @Test func duplicateDatePrecedence() throws {
        let map = try TestSupport.map(
            #"{"Late Arrival": ["11/6/2026"], "No School": ["11/6/2026"]}"#)
        let match = try #require(map.match(day(2026, 11, 6)))
        #expect(match.family == .noSchool)
        #expect(match.hadConflict)

        let map2 = try TestSupport.map(
            #"{"Asynchronous": ["1/20/2027"], "Late Arrival": ["1/20/2027"]}"#)
        #expect(map2.match(day(2027, 1, 20))?.family == .asynchronous)
    }

    @Test func nonArrayValuesSkippedWithWarning() throws {
        let map = try TestSupport.map(
            #"{"Late Arrival": ["9/18/2026"], "meta": {"version": 2}}"#)
        #expect(map.entries.count == 1)
        #expect(map.warnings.count == 1)
    }
}
