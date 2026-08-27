import Testing
import Foundation
@testable import ScheduleKit

@Suite struct PersonalizationTests {
    let monday = day(2026, 9, 14) // Standard day 2026-09-14

    func timeline(_ config: UserConfig, on target: DayKey? = nil,
                  map: DayTypeMap? = nil) -> DayTimeline {
        resolveDay(target ?? monday, inputs: TestSupport.inputs(map: map, config: config))
    }

    @Test func lunch4AOnStandardSplitsPeriodFour() {
        let config = UserConfig(lunch: SplitAssignment(basePeriod: 4, choice: .a))
        let t = timeline(config)
        let lines = TestSupport.lines(t)

        #expect(lines.contains("11:10-11:30 4A lunch Lunch"))
        #expect(lines.contains("11:37-11:57 4B classPeriod 4th Period"))
        #expect(t.blocks.count == 9) // 7 whole periods + 2 halves
        // Other periods are untouched.
        #expect(lines.contains("08:30-09:21 1 classPeriod 1st Period"))
    }

    @Test func halfPeriodViewExpandsEveryAvailableABPeriod() {
        let full = resolveDay(monday, inputs: TestSupport.inputs(), viewMode: .fullPeriods)
        let half = resolveDay(monday, inputs: TestSupport.inputs(), viewMode: .halfPeriods)

        #expect(full.blocks.map(\.id) == (1...8).map(String.init))
        #expect(half.blocks.map(\.id) == (1...8).flatMap { ["\($0)A", "\($0)B"] })
        #expect(half.blocks.allSatisfy { $0.half != nil })
        #expect(half.blocks.first?.start == full.blocks.first?.start)
        #expect(half.blocks.last?.end == full.blocks.last?.end)
    }

    @Test func halfPeriodViewPreservesPersonalizedAssignments() {
        let config = UserConfig(lunch: SplitAssignment(basePeriod: 4, choice: .a))
        let half = resolveDay(
            monday,
            inputs: TestSupport.inputs(config: config),
            viewMode: .halfPeriods)

        #expect(half.blocks.first { $0.id == "4A" }?.role == .lunch)
        #expect(half.blocks.first { $0.id == "4B" }?.role == .classPeriod)
    }

    @Test func halfPeriodViewExpandsExtendedClassesWithoutLosingTheirIdentity() {
        var config = UserConfig(customizations: [
            "2": PeriodCustomization(name: "AP Chemistry", room: "118")
        ])
        config.setClassExtended(anchor: 2, true)
        let half = resolveDay(
            monday,
            inputs: TestSupport.inputs(config: config),
            viewMode: .halfPeriods)

        let chemistryBlocks = half.blocks.filter { ["2A", "2B", "3A"].contains($0.id) }
        #expect(chemistryBlocks.map(\.displayName) == Array(repeating: "AP Chemistry", count: 3))
        #expect(chemistryBlocks.map(\.room) == Array(repeating: "118", count: 3))
        #expect(chemistryBlocks.allSatisfy { $0.customizationID == .period(2) })
    }

    @Test func halfPeriodViewFallsBackWhenScheduleHasNoABTable() throws {
        let map = try TestSupport.map(#"{"Late Arrival": ["9/14/2026"]}"#)
        let half = resolveDay(
            monday,
            inputs: TestSupport.inputs(map: map),
            viewMode: .halfPeriods)

        #expect(half.family == .lateArrival)
        #expect(half.blocks.allSatisfy { $0.half == nil })
    }

    @Test func lunch4BOnStandardFlipsTheHalves() {
        let config = UserConfig(lunch: SplitAssignment(basePeriod: 4, choice: .b))
        let lines = TestSupport.lines(timeline(config))
        #expect(lines.contains("11:10-11:30 4A classPeriod 4th Period"))
        #expect(lines.contains("11:37-11:57 4B lunch Lunch"))
    }

    @Test func fullPeriodLunch() {
        let config = UserConfig(lunch: SplitAssignment(basePeriod: 5, choice: .full))
        let lines = TestSupport.lines(timeline(config))
        #expect(lines.contains("12:02-12:49 5 lunch Lunch"))
    }

    @Test func abLunchFallsBackToFullPeriodOnLateArrival() throws {
        let map = try TestSupport.map(#"{"Late Arrival": ["9/14/2026"]}"#)
        let config = UserConfig(lunch: SplitAssignment(basePeriod: 4, choice: .a))
        let t = timeline(config, map: map)
        #expect(t.family == .lateArrival)
        let lines = TestSupport.lines(t)
        #expect(lines.contains("12:20-12:55 4 lunch Lunch"))
        #expect(!lines.contains { $0.contains("4A") })
    }

    @Test func abLunchFallsBackToFullPeriodOnEarlyDismissal() throws {
        // Spec-mandated: any schedule without A/B subdivisions gives the whole
        // base period to lunch — including finals days.
        let map = try TestSupport.map(#"{"Early Dismissal": ["12/17/2026-12/18/2026"]}"#)
        let config = UserConfig(lunch: SplitAssignment(basePeriod: 4, choice: .b))
        let t = resolveDay(day(2026, 12, 17), inputs: TestSupport.inputs(map: map, config: config))
        let lines = TestSupport.lines(t)
        #expect(lines.contains("11:00-11:40 4 lunch Lunch"))
    }

    @Test func advisoryWorksLikeLunch() {
        let config = UserConfig(
            lunch: SplitAssignment(basePeriod: 5, choice: .a),
            advisory: SplitAssignment(basePeriod: 2, choice: .b))
        let lines = TestSupport.lines(timeline(config))
        #expect(lines.contains("12:02-12:22 5A lunch Lunch"))
        #expect(lines.contains("12:29-12:49 5B classPeriod 5th Period"))
        #expect(lines.contains("09:26-09:46 2A classPeriod 2nd Period"))
        #expect(lines.contains("09:53-10:13 2B advisory Advisory"))
    }

    @Test func lunchAndAdvisoryCanShareAPeriodOnOppositeHalves() {
        let config = UserConfig(
            lunch: SplitAssignment(basePeriod: 4, choice: .b),
            advisory: SplitAssignment(basePeriod: 4, choice: .a))
        let lines = TestSupport.lines(timeline(config))
        #expect(lines.contains("11:10-11:30 4A advisory Advisory"))
        #expect(lines.contains("11:37-11:57 4B lunch Lunch"))
    }

    @Test func conflictingSameHalfResolvesDeterministicallyToLunch() {
        // Settings validation prevents this; the resolver backstop keeps it sane.
        let config = UserConfig(
            lunch: SplitAssignment(basePeriod: 4, choice: .a),
            advisory: SplitAssignment(basePeriod: 4, choice: .a))
        let lines = TestSupport.lines(timeline(config))
        #expect(lines.contains("11:10-11:30 4A lunch Lunch"))
        #expect(lines.contains("11:37-11:57 4B classPeriod 4th Period"))
    }

    @Test func customNamesAndRoomsFollowIdentity() {
        let config = UserConfig(customizations: [
            "3": PeriodCustomization(name: "AP Biology", room: "214"),
            "6": PeriodCustomization(name: "AP Chemistry", room: "118"),
        ])
        let standardLines = TestSupport.lines(timeline(config))
        #expect(standardLines.contains("10:18-11:05 3 classPeriod AP Biology"))

        let block = timeline(config).blocks.first { $0.id == "3" }
        #expect(block?.room == "214")
    }

    @Test func customNamesSurviveFinalsReordering() throws {
        // Early Dismissal rotation 1 runs period 6 first; the name must follow.
        let map = try TestSupport.map(#"{"Early Dismissal": ["12/17/2026-12/18/2026"]}"#)
        let config = UserConfig(customizations: [
            "6": PeriodCustomization(name: "AP Chemistry", room: "118")
        ])
        let t = resolveDay(day(2026, 12, 17), inputs: TestSupport.inputs(map: map, config: config))
        #expect(t.blocks.first?.id == "6")
        #expect(t.blocks.first?.displayName == "AP Chemistry")
    }

    @Test func freePeriodsGetFreeRole() {
        let config = UserConfig(freePeriods: [7])
        let lines = TestSupport.lines(timeline(config))
        #expect(lines.contains("13:46-14:33 7 free Free Period"))
    }

    @Test func freePeriodsIgnoreStoredClassNames() {
        // A stored name belongs to the period's class (kept for when it
        // returns); free time itself is always anonymous.
        let config = UserConfig(
            freePeriods: [7],
            customizations: ["7": PeriodCustomization(name: "AP Chemistry")])
        let lines = TestSupport.lines(timeline(config))
        #expect(lines.contains("13:46-14:33 7 free Free Period"))
    }

    @Test func consecutiveFreePeriodsMergeIntoOneMoment() {
        let config = UserConfig(freePeriods: [6, 7])
        let t = timeline(config)

        // Display list keeps both periods.
        #expect(t.blocks.filter { $0.role == .free }.count == 2)

        // Moment list merges them, absorbing the gap between.
        let freeSpans = t.moments.filter { $0.role == .free }
        #expect(freeSpans.count == 1)
        let span = freeSpans[0]
        #expect(span.start == TestSupport.at(monday, 12, 54))
        #expect(span.end == TestSupport.at(monday, 14, 33))
        #expect(span.blockIDs == ["6", "7"])
        #expect(span.periodID == nil)
        #expect(t.moments.count == t.blocks.count - 1)
    }

    @Test func splitLunchHalvesAreSeparateMoments() {
        let config = UserConfig(lunch: SplitAssignment(basePeriod: 4, choice: .a))
        let t = timeline(config)
        let ids = t.moments.map(\.id)
        #expect(ids.contains("4A"))
        #expect(ids.contains("4B"))
    }

    @Test func lunchInPeriodAbsentFromScheduleVanishes() throws {
        // Odyssey has periods 1–5 only; a period-6 lunch simply doesn't appear.
        let map = try TestSupport.map(#"{"Odyssey": ["9/14/2026"]}"#)
        let config = UserConfig(lunch: SplitAssignment(basePeriod: 6, choice: .full))
        let t = timeline(config, map: map)
        #expect(t.family == .odyssey)
        #expect(t.blocks.map(\.id) == ["homeroom", "1", "2", "3", "4", "5"])
        #expect(!t.blocks.contains { $0.role == .lunch })
    }
}
