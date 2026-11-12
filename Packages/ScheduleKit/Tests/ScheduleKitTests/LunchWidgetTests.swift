import Foundation
import Testing
@testable import ScheduleKit

@Suite struct LunchWidgetTests {
    private let monday = DayKey(year: 2026, month: 9, day: 14)

    @Test(arguments: [nil, Data("broken".utf8), legacyRotationManifest,
                      Data(repeating: 0x20, count: LunchMenuParser.maxBytes + 1)] as [Data?])
    func aMissingOrUnreadableCacheHasNoMenu(cachedData: Data?) {
        // No menu ships with the app, so there is nothing to fall back to.
        #expect(LunchMenuLoader.load(cachedData: cachedData) == nil)

        let entries = LunchWidgetTimelinePlanner.entries(
            from: monday.date()!, cachedData: cachedData,
            inputs: ResolverInputs(catalog: TestSupport.catalog))
        #expect(entries.allSatisfy { $0.menu == nil })
        // The day itself is still a serving day: the widget says the menu is
        // unavailable rather than that there is no lunch.
        #expect(entries[0].isServingDay)
    }

    @Test func widgetsShowTheCachedMenusWithoutTheApp() throws {
        let cached = TestSupport.septemberLunchPayload
        #expect(LunchMenuLoader.load(cachedData: cached) == TestSupport.septemberLunchMenu)

        let entries = LunchWidgetTimelinePlanner.entries(
            from: monday.date()!, cachedData: cached,
            inputs: ResolverInputs(catalog: TestSupport.catalog))
        let expected = try #require(TestSupport.septemberLunchMenu.menu(for: monday))
        #expect(entries.first?.menu == expected)
    }

    @Test func menusRunOutWhereThePublishedWindowEnds() {
        // The app was last opened when the window reached only to Wednesday.
        let cached = TestSupport.lunchPayload(from: day(2026, 9, 7), through: day(2026, 9, 16))
        let entries = LunchWidgetTimelinePlanner.entries(
            from: monday.date()!, cachedData: cached,
            inputs: ResolverInputs(catalog: TestSupport.catalog))

        #expect(entries[0...2].allSatisfy { $0.menu != nil })
        #expect(entries[3].menu == nil && entries[3].isServingDay)
        #expect(entries[4].menu == nil && entries[4].isServingDay)
    }

    @Test func calendarRulesAndTerminalEntry() throws {
        var inputs = ResolverInputs(catalog: TestSupport.catalog)
        inputs.overrides[monday] = DayOverride(day: monday, type: .noSchool)
        let summer = monday.advanced(by: 1)
        inputs.overrides[summer] = DayOverride(day: summer, type: .bell(family: .summer, rotation: nil))
        let cached = TestSupport.septemberLunchPayload
        let entries = LunchWidgetTimelinePlanner.entries(from: monday.date()!, cachedData: cached, inputs: inputs)
        #expect(entries.count == 8)
        // Published menus do not survive the student's own calendar.
        #expect(entries[0].menu == nil && !entries[0].isServingDay)
        #expect(entries[1].menu == nil && !entries[1].isServingDay)
        #expect(entries[2].menu?.sections.count == 6)
        #expect(entries[5].menu == nil && !entries[5].isServingDay)
        // The following Monday has a menu, but the terminal entry stays empty.
        #expect(TestSupport.septemberLunchMenu.menu(for: entries[7].day) != nil)
        #expect(entries[7].menu == nil)
        let expired = LunchWidgetTimelinePlanner.entries(
            from: DayKey(year: 2027, month: 9, day: 14).date()!, cachedData: cached, inputs: inputs)
        #expect(expired.allSatisfy { $0.menu == nil })
    }

    @Test func midnightUsesSchoolTimeAcrossDST() throws {
        let today = DayKey(year: 2026, month: 10, day: 31)
        let entries = LunchWidgetTimelinePlanner.entries(from: today.date()!, cachedData: nil,
                                                          inputs: ResolverInputs(catalog: TestSupport.catalog))
        #expect(entries[2].date.timeIntervalSince(entries[1].date) == 25 * 3600)
        for entry in entries {
            #expect(DayKey(date: entry.date) == entry.day)
            #expect(SchoolTime.calendar.component(.hour, from: entry.date) == 0)
        }
    }

    @Test func lunchReaderDoesNotWriteOrMigrate() throws {
        let name = "lunch-widget-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(throws: (any Error).self) { try SharedStore.readLunchWidgetData(from: defaults) }
        defaults.set(true, forKey: "sk.widgetDataReady")
        let menu = TestSupport.septemberLunchPayload
        defaults.set(menu, forKey: "sk.lunchMenuData")
        defaults.set(Data("private ID".utf8), forKey: "sk.studentID")
        let before = defaults.persistentDomain(forName: name)! as NSDictionary
        let snapshot = try SharedStore.readLunchWidgetData(from: defaults)
        #expect(snapshot.cachedMenu == menu)
        #expect(before == defaults.persistentDomain(forName: name)! as NSDictionary)
    }
}
