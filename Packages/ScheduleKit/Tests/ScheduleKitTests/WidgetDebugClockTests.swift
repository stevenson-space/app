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

    @Test(arguments: [-180 * 86400.0, 0, 180 * 86400.0])
    func lunchTimeTravelPreservesMenusAndMidnightTransitions(offset: TimeInterval) throws {
        let simulated = TestSupport.at(day(2026, 9, 14), 23, 59)
        let realNow = simulated.addingTimeInterval(-offset)
        let clock = WidgetDebugClock(offset: offset)
        let entries = LunchWidgetTimelinePlanner.entries(
            from: clock.scheduleDate(for: realNow), cachedData: nil, inputs: TestSupport.inputs())
        let first = try #require(entries.first)
        #expect(first.day == day(2026, 9, 14))
        #expect(first.menu == (try LunchMenuParser.loadBundled()).menu(for: first.day))
        #expect(clock.realDate(for: first.date) == realNow)
        #expect(entries[1].day == day(2026, 9, 15))
        #expect(clock.realDate(for: entries[1].date) == realNow.addingTimeInterval(60))
        #expect(entries[1].menu != nil)
    }

    @Test func lunchScenariosUseSimulatedSchoolDayOverrides() throws {
        let simulatedDay = day(2026, 9, 14)
        let realNow = TestSupport.at(day(2026, 9, 20), 12, 0)
        let simulated = TestSupport.at(simulatedDay, 12, 0)
        let clock = WidgetDebugClock(offset: simulated.timeIntervalSince(realNow))
        var inputs = TestSupport.inputs()
        inputs.overrides[simulatedDay] = DayOverride(day: simulatedDay, type: .asynchronous)
        let entries = LunchWidgetTimelinePlanner.entries(
            from: clock.scheduleDate(for: realNow), cachedData: nil, inputs: inputs)
        #expect(entries[0].day == simulatedDay)
        #expect(entries[0].menu == nil)
        #expect(!entries[0].isServingDay)
        inputs.overrides.removeValue(forKey: simulatedDay)
        let restored = LunchWidgetTimelinePlanner.entries(
            from: clock.scheduleDate(for: realNow), cachedData: nil, inputs: inputs)
        #expect(restored[0].menu != nil)
        let realEntries = LunchWidgetTimelinePlanner.entries(
            from: WidgetDebugClock().scheduleDate(for: realNow), cachedData: nil, inputs: inputs)
        #expect(realEntries[0].day == day(2026, 9, 20))
        #expect(realEntries[0].menu == nil)
    }

    @Test func invalidOffsetUsesRealTime() {
        #expect(WidgetDebugClock(offset: .nan).offset == 0)
        #expect(WidgetDebugClock(offset: .infinity).offset == 0)
    }
}
#endif
