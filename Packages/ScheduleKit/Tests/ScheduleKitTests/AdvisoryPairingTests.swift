import Testing
import Foundation
@testable import ScheduleKit

@Suite struct AdvisoryPairingTests {
    /// The resolved lines belonging to period 4 (full "4" or the "4A"/"4B"
    /// halves), so a test can assert the *complete* block set and catch any
    /// extra conflicting block, not just presence.
    private func periodFourLines(_ timeline: DayTimeline) -> [String] {
        TestSupport.lines(timeline).filter { line in
            let id = line.split(separator: " ")[1]
            return id == "4" || id == "4A" || id == "4B"
        }
    }

    @Test func advisoryHalfDerivesLunchOppositeHalf() {
        var config = UserConfig()

        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .a)
        #expect(config.advisory == SplitAssignment(basePeriod: 4, choice: .a))
        #expect(config.lunch == SplitAssignment(basePeriod: 4, choice: .b))

        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .b)
        #expect(config.advisory == SplitAssignment(basePeriod: 4, choice: .b))
        #expect(config.lunch == SplitAssignment(basePeriod: 4, choice: .a))

        config.setPairedAdvisory(basePeriod: 5, advisoryHalf: .a)
        #expect(config.advisory == SplitAssignment(basePeriod: 5, choice: .a))
        #expect(config.lunch == SplitAssignment(basePeriod: 5, choice: .b))

        // Upper supported base period, both halves.
        config.setPairedAdvisory(basePeriod: 6, advisoryHalf: .a)
        #expect(config.advisory == SplitAssignment(basePeriod: 6, choice: .a))
        #expect(config.lunch == SplitAssignment(basePeriod: 6, choice: .b))

        config.setPairedAdvisory(basePeriod: 6, advisoryHalf: .b)
        #expect(config.advisory == SplitAssignment(basePeriod: 6, choice: .b))
        #expect(config.lunch == SplitAssignment(basePeriod: 6, choice: .a))
    }

    @Test func outOfRangeBasePeriodIsRejected() {
        var config = UserConfig()
        // Below the 4–6 window.
        config.setPairedAdvisory(basePeriod: 3, advisoryHalf: .a)
        #expect(config.advisory == nil)
        #expect(config.lunch == nil)
        // Above the 4–6 window.
        config.setPairedAdvisory(basePeriod: 7, advisoryHalf: .b)
        #expect(config.advisory == nil)
        #expect(config.lunch == nil)
    }

    @Test func repairingMovesBothAssignmentsTogether() {
        var config = UserConfig(lunch: SplitAssignment(basePeriod: 6, choice: .full))
        config.setPairedAdvisory(basePeriod: 5, advisoryHalf: .b)
        // The old independent lunch is fully replaced — both live in period 5,
        // with lunch taking the half opposite the .b advisory.
        #expect(config.lunch?.basePeriod == 5)
        #expect(config.lunch?.choice == .a)
        #expect(config.advisory?.basePeriod == 5)
    }

    @Test func clearingAdvisoryKeepsTheDerivedLunch() {
        var config = UserConfig()
        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .a)
        config.clearAdvisory()
        #expect(config.advisory == nil)
        #expect(config.lunch == SplitAssignment(basePeriod: 4, choice: .b))
    }

    @Test func pairedConfigResolvesToAdjacentHalves() {
        var config = UserConfig()
        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .a)

        let timeline = resolveDay(day(2026, 9, 14), inputs: TestSupport.inputs(config: config))
        // Period 4 is exactly the advisory half then the lunch half — nothing else.
        #expect(periodFourLines(timeline) == [
            "11:10-11:30 4A advisory Advisory",
            "11:37-11:57 4B lunch Lunch",
        ])
    }

    @Test func advisoryIsSuppressedOnFridaysAndLunchFillsThePeriod() {
        var config = UserConfig()
        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .a) // advisory 4A ⇒ lunch 4B

        // Friday, Sep 18 2026 — a standard A/B day, but advisory doesn't meet:
        // period 4 is one full-period lunch, with no advisory half left behind.
        let friday = resolveDay(day(2026, 9, 18), inputs: TestSupport.inputs(config: config))
        #expect(periodFourLines(friday) == ["11:10-11:57 4 lunch Lunch"])

        // Thursday still splits into exactly the advisory + lunch halves.
        let thursday = resolveDay(day(2026, 9, 17), inputs: TestSupport.inputs(config: config))
        #expect(periodFourLines(thursday) == [
            "11:10-11:30 4A advisory Advisory",
            "11:37-11:57 4B lunch Lunch",
        ])
    }

    @Test func pairedConfigFallsBackToFullPeriodLunchWithoutABTables() throws {
        // Late Arrival has no A/B subdivisions: the shared period renders as a
        // full-period lunch (lunch-wins backstop), matching the lunch spec.
        var config = UserConfig()
        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .b)

        let map = try TestSupport.map(#"{"Late Arrival": ["9/14/2026"]}"#)
        let timeline = resolveDay(day(2026, 9, 14),
                                  inputs: TestSupport.inputs(map: map, config: config))
        // Lunch wins the whole period; period 4 is exactly one full lunch block,
        // with no advisory half also claiming it.
        #expect(periodFourLines(timeline) == ["12:20-12:55 4 lunch Lunch"])
    }
}
