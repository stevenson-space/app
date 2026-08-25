import Testing
import Foundation
@testable import ScheduleKit

@Suite struct NotificationPlannerTests {
    /// Resolved timelines for a date range with the given inputs.
    private func timelines(_ from: DayKey, _ count: Int,
                           map: DayTypeMap? = nil,
                           config: UserConfig = UserConfig()) -> [DayTimeline] {
        var result: [DayTimeline] = []
        var day = from
        for _ in 0..<count {
            result.append(resolveDay(day, inputs: TestSupport.inputs(map: map, config: config)))
            day = day.advanced(by: 1)
        }
        return result
    }

    private func earlyMorning(_ day: DayKey) -> Date {
        TestSupport.at(day, 0, 5)
    }

    @Test func disabledPrefsPlanNothing() {
        let days = timelines(day(2026, 9, 14), 5)
        let planned = NotificationPlanner.plan(
            days: days, prefs: NotificationPrefs(), now: earlyMorning(day(2026, 9, 14)))
        #expect(planned.isEmpty)
    }

    @Test func standardDayBlockEndAlerts() {
        let prefs = NotificationPrefs(blockEndEnabled: true, blockEndLeadMinutes: 5)
        let monday = day(2026, 9, 14)
        let planned = NotificationPlanner.plan(
            days: timelines(monday, 1), prefs: prefs, now: earlyMorning(monday))

        #expect(planned.count == 8)
        #expect(planned.first?.identifier == "end.2026-09-14.1")
        // Period 1 ends 9:21; lead 5 → fires 9:16.
        #expect(planned.first?.time == HourMinute(hour: 9, minute: 16))
        #expect(planned.first?.title == "Next: 2nd Period")
        #expect(planned.first?.body == "Starts at 9:26 AM")
        #expect(planned.last?.title == "8th Period ends in 5 min")
        #expect(planned.last?.body == "Last block of the day")
        // No morning alert on a standard day even with morning enabled.
        let withMorning = NotificationPlanner.plan(
            days: timelines(monday, 1),
            prefs: NotificationPrefs(blockEndEnabled: true, morningEnabled: true),
            now: earlyMorning(monday))
        #expect(!withMorning.contains { $0.identifier.hasPrefix("morning.") })
    }

    @Test func upcomingClassUsesCustomNameAndRoom() {
        let config = UserConfig(customizations: [
            "2": PeriodCustomization(name: "AP Biology", room: "214"),
        ])
        let prefs = NotificationPrefs(blockEndEnabled: true, blockEndLeadMinutes: 5)
        let monday = day(2026, 9, 14)
        let planned = NotificationPlanner.plan(
            days: timelines(monday, 1, config: config), prefs: prefs, now: earlyMorning(monday))

        #expect(planned.first?.title == "Next: AP Biology")
        #expect(planned.first?.body == "Room 214")
    }

    @Test func upcomingClassWithoutRoomShowsStartTimeInPreferredFormat() {
        let config = UserConfig(customizations: [
            "2": PeriodCustomization(name: "AP Biology"),
        ])
        let prefs = NotificationPrefs(blockEndEnabled: true, blockEndLeadMinutes: 5)
        let monday = day(2026, 9, 14)
        let planned = NotificationPlanner.plan(
            days: timelines(monday, 1, config: config), prefs: prefs,
            now: earlyMorning(monday), timeFormat: .twentyFourHour)

        #expect(planned.first?.title == "Next: AP Biology")
        #expect(planned.first?.body == "Starts at 9:26")
    }

    @Test func freePeriodsAndMergedSpansAreSkipped() {
        let config = UserConfig(freePeriods: [6, 7])
        let prefs = NotificationPrefs(blockEndEnabled: true)
        let monday = day(2026, 9, 14)
        let planned = NotificationPlanner.plan(
            days: timelines(monday, 1, config: config), prefs: prefs, now: earlyMorning(monday))
        #expect(planned.count == 6)
        #expect(!planned.contains { $0.identifier.contains(".6") || $0.identifier.contains(".7") })
    }

    @Test func finalFreePeriodIsCalledOutAfterTheLastClass() {
        let config = UserConfig(freePeriods: [8])
        let prefs = NotificationPrefs(blockEndEnabled: true)
        let monday = day(2026, 9, 14)
        let planned = NotificationPlanner.plan(
            days: timelines(monday, 1, config: config), prefs: prefs, now: earlyMorning(monday))

        #expect(planned.count == 7)
        #expect(planned.last?.identifier == "end.2026-09-14.7")
        #expect(planned.last?.body == "You're free for the rest of the day")
    }

    @Test func consecutiveFinalFreePeriodsAreCalledOutAfterTheLastClass() {
        let config = UserConfig(freePeriods: [7, 8])
        let prefs = NotificationPrefs(blockEndEnabled: true)
        let monday = day(2026, 9, 14)
        let planned = NotificationPlanner.plan(
            days: timelines(monday, 1, config: config), prefs: prefs, now: earlyMorning(monday))

        #expect(planned.count == 6)
        #expect(planned.last?.identifier == "end.2026-09-14.6")
        #expect(planned.last?.body == "You're free for the rest of the day")
    }

    @Test func lunchGetsAnAlertToo() {
        let config = UserConfig(lunch: SplitAssignment(basePeriod: 4, choice: .a))
        let prefs = NotificationPrefs(blockEndEnabled: true, blockEndLeadMinutes: 5)
        let monday = day(2026, 9, 14)
        let planned = NotificationPlanner.plan(
            days: timelines(monday, 1, config: config), prefs: prefs, now: earlyMorning(monday))

        let lunch = planned.first { $0.identifier == "end.2026-09-14.4A" }
        #expect(lunch != nil)
        #expect(lunch?.title == "Next: 4th Period")
        #expect(lunch?.body == "Starts at 11:37 AM")
        // 9 alerts: 7 whole periods + both halves of period 4.
        #expect(planned.count == 9)
    }

    @Test func morningAlertOnNonStandardAndAsyncDays() throws {
        let map = try TestSupport.map(
            #"{"Late Arrival": ["9/18/2026"], "Asynchronous": ["9/17/2026"]}"#)
        let prefs = NotificationPrefs(morningEnabled: true,
                                      morningTime: HourMinute(hour: 6, minute: 45))
        let thursday = day(2026, 9, 17)
        let planned = NotificationPlanner.plan(
            days: timelines(thursday, 2, map: map), prefs: prefs, now: earlyMorning(thursday))

        #expect(planned.count == 2)
        let async = try #require(planned.first { $0.day == thursday })
        #expect(async.identifier == "morning.2026-09-17")
        #expect(async.title == "Asynchronous E-Learning Day")
        #expect(async.time == HourMinute(hour: 6, minute: 45))

        let lateArrival = try #require(planned.first { $0.day == day(2026, 9, 18) })
        #expect(lateArrival.title == "Today: Late Arrival")
        #expect(lateArrival.body == "1st Period starts at 10:30 AM.")
    }

    @Test func noMorningAlertsForWeekendsBreaksHolidays() throws {
        let map = try TestSupport.map(#"{"No School": ["11/25/2026"]}"#)
        let prefs = NotificationPrefs(blockEndEnabled: true, morningEnabled: true)
        // Sat Sep 19, Sun Sep 20; holiday Nov 25; winter break day Dec 23.
        var days = timelines(day(2026, 9, 19), 2, map: map)
        days += timelines(day(2026, 11, 25), 1, map: map)
        days += timelines(day(2026, 12, 23), 1, map: map)
        let planned = NotificationPlanner.plan(
            days: days, prefs: prefs, now: earlyMorning(day(2026, 9, 19)))
        #expect(planned.isEmpty)
    }

    @Test func blocksShorterThanLeadAreSkipped() throws {
        // Odyssey's homeroom is 10 minutes; a 15-minute lead can't announce it.
        let map = try TestSupport.map(#"{"Odyssey": ["9/14/2026"]}"#)
        let prefs = NotificationPrefs(blockEndEnabled: true, blockEndLeadMinutes: 15)
        let monday = day(2026, 9, 14)
        let planned = NotificationPlanner.plan(
            days: timelines(monday, 1, map: map), prefs: prefs, now: earlyMorning(monday))
        #expect(!planned.contains { $0.identifier.hasSuffix(".homeroom") })
        #expect(planned.count == 5)
    }

    @Test func zeroLeadFiresExactlyAtTheBell() {
        let prefs = NotificationPrefs(blockEndEnabled: true, blockEndLeadMinutes: 0)
        let monday = day(2026, 9, 14)
        let planned = NotificationPlanner.plan(
            days: timelines(monday, 1), prefs: prefs, now: earlyMorning(monday))

        #expect(planned.count == 8)
        // Period 1 ends 9:21; zero lead fires at 9:21 sharp.
        #expect(planned.first?.time == HourMinute(hour: 9, minute: 21))
        #expect(planned.first?.title == "Next: 2nd Period")
        #expect(planned.first?.body == "Starts at 9:26 AM")
        #expect(planned.last?.title == "8th Period is over")
    }

    @Test func pastFiresAreDropped() {
        let prefs = NotificationPrefs(blockEndEnabled: true, blockEndLeadMinutes: 5,
                                      morningEnabled: true)
        let monday = day(2026, 9, 14)
        // 12:30 PM: periods 1–4 done, period 5 in progress (12:02–12:49).
        let planned = NotificationPlanner.plan(
            days: timelines(monday, 1), prefs: prefs, now: TestSupport.at(monday, 12, 30))
        #expect(planned.count == 4) // periods 5, 6, 7, 8
        #expect(planned.first?.identifier == "end.2026-09-14.5")
        #expect(!planned.contains { $0.identifier.hasPrefix("morning.") })
    }

    @Test func budgetPacksWholeDays() {
        let prefs = NotificationPrefs(blockEndEnabled: true)
        // Two full school weeks (weekends contribute nothing): 10 × 8 = 80 > 56.
        let start = day(2026, 9, 14)
        let planned = NotificationPlanner.plan(
            days: timelines(start, 14), prefs: prefs, now: earlyMorning(start))

        #expect(planned.count == 56) // 7 whole days × 8
        #expect(planned.count % 8 == 0)
        let coveredDays = Set(planned.map(\.day))
        #expect(coveredDays.count == 7)
        // Day 8 (Wed Sep 23) is entirely absent, not half-present.
        #expect(!coveredDays.contains(day(2026, 9, 23)))
    }

    @Test func dayOneAloneIsTruncatedNotDropped() {
        let prefs = NotificationPrefs(blockEndEnabled: true)
        let monday = day(2026, 9, 14)
        let planned = NotificationPlanner.plan(
            days: timelines(monday, 1), prefs: prefs, now: earlyMorning(monday), budget: 3)
        #expect(planned.count == 3)
    }

    @Test func identifiersAreStableAndPrefixed() throws {
        let prefs = NotificationPrefs(blockEndEnabled: true, morningEnabled: true)
        let map = try TestSupport.map(#"{"Late Arrival": ["9/18/2026"]}"#)
        let friday = day(2026, 9, 18)
        let planned = NotificationPlanner.plan(
            days: timelines(friday, 1, map: map), prefs: prefs, now: earlyMorning(friday))
        // Guard against a vacuous pass: the scenario must actually plan alerts.
        #expect(!planned.isEmpty)
        for notification in planned {
            #expect(NotificationPlanner.identifierPrefixes.contains {
                notification.identifier.hasPrefix($0)
            })
        }
    }
}
