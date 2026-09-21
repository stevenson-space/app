import Foundation
import Testing
@testable import ScheduleKit

@Suite struct LunchOverrideTests {
    private let monday = day(2026, 9, 14)

    @Test func everyOverrideKeepsAppAndWidgetInAgreement() throws {
        let menu = try LunchMenuParser.loadBundled()
        let published = try #require(menu.menu(for: monday))
        let types: [OverrideType] = [
            .noSchool, .asynchronous,
            .bell(family: .summer, rotation: nil),
            .bell(family: .standard, rotation: nil),
            .bell(family: .lateArrival, rotation: nil),
            .bell(family: .odyssey, rotation: nil),
            .bell(family: .activityPeriod, rotation: nil),
            .bell(family: .pmAssembly, rotation: nil),
            .bell(family: .earlyDismissal, rotation: .rotation1),
            .bell(family: .earlyDismissal, rotation: .rotation2),
            .bell(family: .earlyDismissal, rotation: nil),
        ]
        for type in types {
            var inputs = TestSupport.inputs()
            inputs.overrides[monday] = DayOverride(day: monday, type: type)
            let serves: Bool
            switch type {
            case .noSchool, .asynchronous, .bell(family: .summer, rotation: _): serves = false
            case .bell: serves = true
            }
            let expected = serves ? published : nil
            #expect(LunchMenuLoader.menu(menu, for: monday, inputs: inputs) == expected)
            let entry = try #require(LunchWidgetTimelinePlanner.entries(
                from: monday.date()!, cachedData: nil, inputs: inputs).first)
            #expect(entry.menu == expected)
            #expect(entry.isServingDay == serves)
            // An override never shifts another date's dishes or rotation.
            let tuesday = monday.advanced(by: 1)
            #expect(LunchMenuLoader.menu(menu, for: tuesday, inputs: inputs) == menu.menu(for: tuesday))
        }
    }

    @Test func replacingAndRemovingOverridesRestoresCalendarRules() throws {
        let menu = try LunchMenuParser.loadBundled()
        let map = try TestSupport.map(#"{"No School":["09/14/2026"]}"#)
        var inputs = TestSupport.inputs(map: map)
        #expect(LunchMenuLoader.menu(menu, for: monday, inputs: inputs) == nil)
        inputs.overrides[monday] = DayOverride(day: monday, type: .bell(family: .standard, rotation: nil))
        #expect(LunchMenuLoader.menu(menu, for: monday, inputs: inputs) == menu.menu(for: monday))
        inputs.overrides[monday] = DayOverride(day: monday, type: .asynchronous)
        #expect(LunchMenuLoader.menu(menu, for: monday, inputs: inputs) == nil)
        inputs.overrides.removeValue(forKey: monday)
        #expect(LunchMenuLoader.menu(menu, for: monday, inputs: inputs) == nil)
        // Removing a closure override on a normal weekday restores its menu.
        inputs.map = nil
        inputs.overrides[monday] = DayOverride(day: monday, type: .noSchool)
        #expect(LunchMenuLoader.menu(menu, for: monday, inputs: inputs) == nil)
        inputs.overrides.removeValue(forKey: monday)
        #expect(LunchMenuLoader.menu(menu, for: monday, inputs: inputs) == menu.menu(for: monday))
    }

    @Test func bellOverridesCannotInventUnpublishedMenus() throws {
        let menu = try LunchMenuParser.loadBundled()
        for date in [day(2026, 9, 19), day(2027, 6, 1)] {
            let inputs = TestSupport.inputs(overrides: [
                date: DayOverride(day: date, type: .bell(family: .standard, rotation: nil)),
            ])
            #expect(resolveDay(date, inputs: inputs).isSchoolDay)
            #expect(LunchMenuLoader.menu(menu, for: date, inputs: inputs) == nil)
            let entry = try #require(LunchWidgetTimelinePlanner.entries(
                from: date.date()!, cachedData: nil, inputs: inputs).first)
            #expect(entry.menu == nil)
            #expect(entry.isServingDay == !date.isWeekend)
        }
    }

    @Test func persistedOverrideRemovalReachesLunchWidget() throws {
        let suite = "lunch-override-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SharedStore(defaults: defaults, secrets: InMemorySecretStore())
        defaults.set(true, forKey: "sk.widgetDataReady")
        store.overrides = [DayOverride(day: monday, type: .noSchool)]
        let closed = try SharedStore.readLunchWidgetData(from: defaults)
        #expect(LunchMenuLoader.menu(try LunchMenuParser.loadBundled(), for: monday,
                                    inputs: closed.schedule.resolverInputs(catalog: TestSupport.catalog)) == nil)
        store.overrides = []
        let restored = try SharedStore.readLunchWidgetData(from: defaults)
        #expect(LunchMenuLoader.menu(try LunchMenuParser.loadBundled(), for: monday,
                                    inputs: restored.schedule.resolverInputs(catalog: TestSupport.catalog)) != nil)
    }
}
