import Testing
import Foundation
@testable import ScheduleKit

@Suite struct AdvisoryPairingTests {
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
        // The old independent lunch is fully replaced — both live in period 5.
        #expect(config.lunch?.basePeriod == 5)
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
        let lines = TestSupport.lines(timeline)
        #expect(lines.contains("11:10-11:30 4A advisory Advisory"))
        #expect(lines.contains("11:37-11:57 4B lunch Lunch"))
    }

    @Test func pairedConfigFallsBackToFullPeriodLunchWithoutABTables() throws {
        // Late Arrival has no A/B subdivisions: the shared period renders as a
        // full-period lunch (lunch-wins backstop), matching the lunch spec.
        var config = UserConfig()
        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .b)

        let map = try TestSupport.map(#"{"Late Arrival": ["9/14/2026"]}"#)
        let timeline = resolveDay(day(2026, 9, 14),
                                  inputs: TestSupport.inputs(map: map, config: config))
        let lines = TestSupport.lines(timeline)
        #expect(lines.contains("12:20-12:55 4 lunch Lunch"))
        // Lunch wins the whole period; advisory must not also claim period 4.
        #expect(!lines.contains { $0.contains(" advisory ") })
    }
}
