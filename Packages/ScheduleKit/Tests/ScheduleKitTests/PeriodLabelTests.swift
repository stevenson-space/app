import Foundation
import Testing
@testable import ScheduleKit

@Suite struct PeriodLabelTests {
    private let monday = day(2026, 9, 14)

    private func span(_ timeline: DayTimeline, _ hour: Int, _ minute: Int) -> ResolvedSpan? {
        if case .inBlock(let current, _) = momentState(at: TestSupport.at(monday, hour, minute), in: timeline) {
            return current
        }
        return nil
    }

    @Test func singleBlocksKeepTheirOwnLabel() throws {
        let timeline = resolveDay(monday, inputs: TestSupport.inputs())
        let second = try #require(span(timeline, 9, 30))
        #expect(timeline.periodLabel(for: second) == "2")
    }

    @Test func mergedFreePeriodsReadAsARange() throws {
        let timeline = resolveDay(monday, inputs: TestSupport.inputs(config: UserConfig(freePeriods: [6, 7])))
        let free = try #require(span(timeline, 13, 0))
        #expect(free.blockIDs.count == 2)
        #expect(timeline.periodLabel(for: free) == "6–7")
    }

    @Test func aRunStartingOnAHalfNamesThatHalf() throws {
        var config = UserConfig(freePeriods: [5])
        config.setSlot(period: 4, half: .b, to: .free)
        let timeline = resolveDay(monday, inputs: TestSupport.inputs(config: config))
        let free = try #require(span(timeline, 12, 10))
        #expect(free.blockIDs.count == 2)
        #expect(timeline.periodLabel(for: free) == "4B–5")
    }
}
