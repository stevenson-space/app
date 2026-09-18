import Foundation
import Testing
@testable import ScheduleKit

@Suite struct WidgetTimelineTests {
    let monday = day(2026, 9, 14)

    private func entry(at date: Date, inputs: ResolverInputs? = nil) -> WidgetScheduleEntry {
        WidgetTimelinePlanner.plan(from: date, inputs: inputs ?? TestSupport.inputs()).entries[0]
    }

    @Test func leadInAndCompletionHaveExactBoundaries() {
        let before = entry(at: TestSupport.at(monday, 8, 14, 59))
        #expect(!before.isLeadIn)
        #expect(before.countdownInterval == nil)
        #expect(before.focus?.id == "1")
        let lead = entry(at: TestSupport.at(monday, 8, 15))
        #expect(lead.isLeadIn)
        #expect(lead.countdownInterval == TestSupport.at(monday, 8, 15)...TestSupport.at(monday, 8, 30))
        let start = entry(at: TestSupport.at(monday, 8, 30))
        #expect(!start.isLeadIn)
        #expect(start.countdownInterval?.upperBound == TestSupport.at(monday, 9, 21))
        #expect(!entry(at: TestSupport.at(monday, 15, 24, 59)).isFinished)
        let finished = entry(at: TestSupport.at(monday, 15, 25))
        #expect(finished.isFinished)
        #expect(finished.countdownInterval == nil)
        #expect(entry(at: TestSupport.at(monday, 15, 29, 59)).isFinished)
        #expect(!entry(at: TestSupport.at(monday, 15, 30)).isFinished)
        #expect(finished.nextSchoolDay?.day == monday.advanced(by: 1))
    }

    @Test(arguments: BellFamily.allCases)
    func everyFamilyUsesActualBoundaries(family: BellFamily) throws {
        let override = DayOverride(day: monday, type: .bell(family: family, rotation: .rotation1))
        var config = UserConfig(freePeriods: [6, 7])
        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .a)
        let inputs = TestSupport.inputs(overrides: [monday: override], config: config)
        let plan = WidgetTimelinePlanner.plan(from: monday.date()!, inputs: inputs)
        let resolved = resolveDay(monday, inputs: inputs, freePeriodGrouping: .separate)
        let first = try #require(resolved.firstBell)
        let last = try #require(resolved.lastBell)
        let dates = Set(plan.entries.map(\.date))
        #expect(dates.contains(first.addingTimeInterval(-900)))
        #expect(dates.contains(last.addingTimeInterval(300)))
        for block in resolved.blocks {
            #expect(dates.contains(block.start))
            #expect(dates.contains(block.end))
            let atStart = try #require(plan.entries.first { $0.date == block.start })
            #expect(atStart.focus?.id == block.id)
            #expect(atStart.countdownInterval?.upperBound == block.end)
            let atEnd = try #require(plan.entries.first { $0.date == block.end })
            #expect(atEnd.state == momentState(at: block.end, in: resolved))
            if case .passing(_, let next, _) = atEnd.state {
                #expect(atEnd.focus?.id == next.id)
                #expect(atEnd.countdownInterval?.upperBound == next.start)
            }
        }
        #expect(plan.entries.allSatisfy { $0.state == momentState(at: $0.date, in: $0.timeline) })
        #expect(dates.count == plan.entries.count)
        #expect(plan.entries.map(\.date) == plan.entries.map(\.date).sorted())
        #expect(plan.entries.count < 200) // Boundaries, never one entry per second.
    }

    @Test func consecutiveFreePeriodsKeepTheirPassingGap() throws {
        let inputs = TestSupport.inputs(config: UserConfig(freePeriods: [6, 7]))
        let separate = resolveDay(monday, inputs: inputs, freePeriodGrouping: .separate)
        let combined = resolveDay(monday, inputs: inputs)
        #expect(separate.blocks == combined.blocks)
        #expect(combined.moments.contains { $0.blockIDs == ["6", "7"] })
        let first = try #require(separate.blocks.first { $0.id == "6" })
        let second = try #require(separate.blocks.first { $0.id == "7" })
        let passing = entry(at: first.end, inputs: inputs)
        guard case .passing(_, let next, _) = passing.state else {
            Issue.record("Free periods must have a passing state"); return
        }
        #expect(next.id == "7")
        #expect(passing.countdownInterval?.upperBound == second.start)
        #expect(entry(at: second.start, inputs: inputs).countdownInterval?.upperBound == second.end)
        guard case .inBlock(let span, _) = momentState(at: first.end, in: combined) else {
            Issue.record("Existing combined behavior changed"); return
        }
        #expect(span.blockIDs == ["6", "7"])
    }

    @Test func extendedClassesKeepIdentityEmojiAndAbsorbInternalBells() throws {
        var config = UserConfig()
        config.setClassExtended(anchor: 2, true)
        config.lunch = SplitAssignment(basePeriod: 3, choice: .b)
        config.customizations["2"] = PeriodCustomization(name: "Long Personalized Chemistry Class", room: "118", emoji: "⚗️")
        config.timeFormat = .twentyFourHour
        let inputs = TestSupport.inputs(config: config)
        let current = entry(at: TestSupport.at(monday, 10, 15), inputs: inputs)
        let focus = try #require(current.focus)
        #expect(focus.id == "2+3A")
        #expect(focus.room == "118")
        #expect(focus.displayName == "Long Personalized Chemistry Class")
        #expect(ScheduleStyle.emoji(for: focus, config: config) == "⚗️")
        #expect(current.countdownInterval?.upperBound == TestSupport.at(monday, 10, 38))
        #expect(current.upcoming?.role == .lunch)
        #expect(TimeDisplay.time(focus.start, config.timeFormat) == "9:26")
        #expect(TimeDisplay.time(focus.end, .twelveHour) == "10:38 AM")
    }

    @Test func finalsRotationsAndZeroLengthGap() throws {
        let map = try TestSupport.map(#"{"Early Dismissal": ["12/17/2026-12/18/2026"]}"#)
        let inputs = TestSupport.inputs(map: map)
        for (date, firstID) in [(day(2026, 12, 17), "6"), (day(2026, 12, 18), "5")] {
            let start = entry(at: TestSupport.at(date, 8, 30), inputs: inputs)
            #expect(start.focus?.id == firstID)
            let makeup = entry(at: TestSupport.at(date, 11, 40), inputs: inputs)
            #expect(makeup.focus?.id == "makeup")
            guard case .inBlock = makeup.state else { Issue.record("Zero gap became passing"); return }
        }
    }

    @Test func lateArrivalLeadInUsesAdjustedStart() throws {
        let map = try TestSupport.map(#"{"Late Arrival": ["9/18/2026"]}"#)
        let inputs = TestSupport.inputs(map: map)
        let date = day(2026, 9, 18)
        #expect(!entry(at: TestSupport.at(date, 10, 14, 59), inputs: inputs).isLeadIn)
        let lead = entry(at: TestSupport.at(date, 10, 15), inputs: inputs)
        #expect(lead.isLeadIn)
        #expect(lead.countdownInterval?.upperBound == TestSupport.at(date, 10, 30))
    }

    @Test func noPeriodDaysNeverInventTimersAndSkipAsyncInNextDaySearch() throws {
        let map = try TestSupport.map(#"{"Asynchronous": ["9/21/2026"], "No School": ["9/22/2026"], "Unknown Event": ["9/23/2026"]}"#)
        let inputs = TestSupport.inputs(map: map)
        for date in [day(2026, 9, 19), day(2026, 9, 21), day(2026, 9, 22), day(2026, 9, 23)] {
            let result = entry(at: TestSupport.at(date, 9, 0), inputs: inputs)
            #expect(result.countdownInterval == nil)
            #expect(result.focus == nil)
            #expect(result.nextSchoolDay?.day == day(2026, 9, 24))
        }
        #expect(entry(at: TestSupport.at(day(2026, 9, 23), 9, 0), inputs: inputs).state == .unknownSchedule(name: "Unknown Event"))
        let holiday = entry(at: TestSupport.at(day(2026, 12, 23), 9, 0))
        #expect(holiday.state == .breakDay(label: "Winter Break"))
        #expect(holiday.nextSchoolDay?.day ?? monday > day(2026, 12, 30))
    }

    @Test func noKnownUpcomingDayAndMissingMap() {
        let farFuture = entry(at: day(2040, 9, 14).date()!)
        #expect(farFuture.nextSchoolDay == nil)
        #expect(farFuture.countdownInterval == nil)
        let defaultDay = entry(at: TestSupport.at(monday, 9, 0))
        #expect(defaultDay.focus?.displayName == "1st Period")
        #expect(defaultDay.timeline.provenance == .defaultStandard)
    }

    @Test(arguments: [day(2026, 11, 1), day(2027, 3, 14)])
    func sevenCalendarDaysAndMidnightReloadAcrossDST(date: DayKey) {
        let plan = WidgetTimelinePlanner.plan(from: date.date()!, inputs: TestSupport.inputs())
        #expect(plan.reloadAfter == date.advanced(by: 1).date())
        let hours = plan.reloadAfter.timeIntervalSince(date.date()!) / 3600
        #expect(hours == (date.month == 11 ? 25 : 23))
        for offset in 0..<7 {
            #expect(plan.entries.contains { $0.date == date.advanced(by: offset).date() })
        }
        #expect(plan.entries.last!.date < date.advanced(by: 7).date()!)
        let schoolStart = TestSupport.at(date.advanced(by: 1), 8, 30)
        #expect(plan.entries.first { $0.date == schoolStart }?.focus?.id == "1")
    }

    @Test func currentEntryUsesChicagoDayEvenWhenUTCIsTomorrow() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-15T02:00:00Z"))
        let result = entry(at: instant)
        #expect(result.timeline.day == monday)
        #expect(result.state == .afterSchool)
        #expect(result.date == instant)
    }

    @Test func deepLinkOnlyAcceptsHomeToday() {
        #expect(WidgetTimelinePlanner.isHomeURL(WidgetTimelinePlanner.homeURL))
        #expect(!WidgetTimelinePlanner.isHomeURL(URL(string: "stevenson-space://settings/today")!))
        #expect(!WidgetTimelinePlanner.isHomeURL(URL(string: "https://home/today")!))
    }
}
