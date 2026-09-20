#if DEBUG
import Foundation
import Testing
@testable import ScheduleKit

@Suite struct WidgetDebugClockTests {
    @Test(arguments: [-180 * 86400.0, 0, 180 * 86400.0])
    func timeTravelPreservesCountdownsTransitionsAndReloads(offset: TimeInterval) throws {
        let simulated = TestSupport.at(day(2026, 9, 14), 9, 20)
        let realNow = simulated.addingTimeInterval(-offset)
        let clock = WidgetDebugClock(offset: offset)
        let plan = WidgetTimelinePlanner.plan(from: clock.scheduleDate(for: realNow),
                                             inputs: TestSupport.inputs())
        let first = try #require(plan.entries.first)
        #expect(first.focus?.id == "1")
        #expect(clock.realDate(for: first.date) == realNow)
        let timer = clock.realInterval(for: try #require(first.countdownInterval))
        #expect(timer == realNow...realNow.addingTimeInterval(60))
        let next = try #require(plan.entries.dropFirst().first)
        #expect(clock.realDate(for: next.date) == timer.upperBound)
        guard case .passing = next.state else {
            Issue.record("The simulated period must transition to passing"); return
        }
        #expect(clock.realDate(for: plan.reloadAfter).timeIntervalSince(realNow)
                == plan.reloadAfter.timeIntervalSince(simulated))
        #expect(clock.realDate(for: plan.reloadAfter) > realNow)
    }

    @Test func invalidOffsetUsesRealTime() {
        #expect(WidgetDebugClock(offset: .nan).offset == 0)
        #expect(WidgetDebugClock(offset: .infinity).offset == 0)
    }
}
#endif
