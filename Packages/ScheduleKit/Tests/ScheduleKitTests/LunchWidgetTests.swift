import Foundation
import Testing
@testable import ScheduleKit

@Suite struct LunchWidgetTests {
    @Test func invalidAndExpiredCachesFallBackToBundledMenu() throws {
        let today = DayKey(year: 2026, month: 9, day: 14)
        let bundled = try LunchMenuParser.loadBundled()
        #expect(LunchMenuLoader.load(cachedData: Data("broken".utf8), on: today) == bundled)
        var json = try #require(JSONSerialization.jsonObject(with: LunchMenuParser.bundledData()) as? [String: Any])
        json["validTo"] = "2026-08-31"
        json["semesterSwitch"] = "2026-08-20"
        let expired = try JSONSerialization.data(withJSONObject: json)
        #expect(LunchMenuLoader.load(cachedData: expired, on: today) == bundled)
    }

    @Test func validCacheWins() throws {
        let today = DayKey(year: 2026, month: 9, day: 14)
        var json = try #require(JSONSerialization.jsonObject(with: LunchMenuParser.bundledData()) as? [String: Any])
        json["offset"] = 1
        let cached = try JSONSerialization.data(withJSONObject: json)
        #expect(LunchMenuLoader.load(cachedData: cached, on: today) == (try LunchMenuParser.parse(cached)))
    }

    @Test func calendarRulesAndTerminalEntry() throws {
        let today = DayKey(year: 2026, month: 9, day: 14)
        var inputs = ResolverInputs(catalog: TestSupport.catalog)
        inputs.overrides[today] = DayOverride(day: today, type: .noSchool)
        let summer = today.advanced(by: 1)
        inputs.overrides[summer] = DayOverride(day: summer, type: .bell(family: .summer, rotation: nil))
        let entries = LunchWidgetTimelinePlanner.entries(from: today.date()!, cachedData: nil, inputs: inputs)
        #expect(entries.count == 8)
        #expect(entries[0].menu == nil && !entries[0].isServingDay)
        #expect(entries[1].menu == nil && !entries[1].isServingDay)
        #expect(entries[2].menu?.sections.count == 6)
        #expect(entries[5].menu == nil && !entries[5].isServingDay)
        #expect(entries[7].menu == nil)
        let expired = LunchWidgetTimelinePlanner.entries(
            from: DayKey(year: 2027, month: 9, day: 14).date()!, cachedData: nil, inputs: inputs)
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
        let menu = try LunchMenuParser.bundledData()
        defaults.set(menu, forKey: "sk.lunchMenuData")
        defaults.set(Data("private ID".utf8), forKey: "sk.studentID")
        let before = defaults.persistentDomain(forName: name)! as NSDictionary
        let snapshot = try SharedStore.readLunchWidgetData(from: defaults)
        #expect(snapshot.cachedMenu == menu)
        #expect(before == defaults.persistentDomain(forName: name)! as NSDictionary)
    }
}
