import Foundation
import Testing
@testable import ScheduleKit

@Suite struct LunchWidgetTests {
    @Test(arguments: [nil, Data("broken".utf8)] as [Data?])
    func unavailableBundleFallsBackToValidCache(bundledData: Data?) throws {
        let cachedData = try LunchMenuParser.bundledData()
        let cached = try LunchMenuParser.parse(cachedData)
        let loaded = LunchMenuLoader.loadWithSource(cachedData: cachedData, bundledData: bundledData)
        #expect(loaded.menu == cached)
        #expect(!loaded.isBundled)
        for cachedData in [nil, Data("broken cache".utf8)] as [Data?] {
            let unavailable = LunchMenuLoader.loadWithSource(cachedData: cachedData, bundledData: bundledData)
            #expect(unavailable.menu == nil)
            #expect(!unavailable.isBundled)
        }
    }

    @Test(arguments: [nil, Data("broken".utf8)] as [Data?])
    func fallbackSourceClearsWhenMatchingCacheIsAvailable(cachedData: Data?) throws {
        let bundledData = try LunchMenuParser.bundledData()
        let fallback = LunchMenuLoader.loadWithSource(cachedData: cachedData)
        #expect(fallback.menu == (try LunchMenuParser.parse(bundledData)))
        #expect(fallback.isBundled)

        // Even identical dishes are cached data once a matching fetch is saved.
        let refreshed = LunchMenuLoader.loadWithSource(cachedData: bundledData)
        #expect(refreshed.menu == fallback.menu)
        #expect(!refreshed.isBundled)
    }

    @Test func invalidCachesFallBackToBundledMenu() throws {
        let bundled = try LunchMenuParser.loadBundled()
        #expect(LunchMenuLoader.load(cachedData: Data("broken".utf8)) == bundled)
        var json = try #require(JSONSerialization.jsonObject(with: LunchMenuParser.bundledData()) as? [String: Any])
        json["stations"] = [:]
        let invalid = try JSONSerialization.data(withJSONObject: json)
        #expect(LunchMenuLoader.load(cachedData: invalid) == bundled)
        #expect(LunchMenuLoader.load(cachedData: Data(repeating: 0x20, count: LunchMenuParser.maxBytes + 1)) == bundled)
    }

    @Test(arguments: ["matching", "validFrom", "validTo", "semesterSwitch", "offset", "previousYear"])
    func cacheRequiresMatchingBundledRotationSettings(changedSetting: String) throws {
        let today = DayKey(year: 2026, month: 9, day: 14)
        var json = try #require(JSONSerialization.jsonObject(with: LunchMenuParser.bundledData()) as? [String: Any])
        let bundled = try LunchMenuParser.loadBundled()
        var stations = try #require(json["stations"] as? [String: Any])
        stations["comfort"] = ["cadence": "weekly",
                               "data": Array(repeating: "Cached comfort", count: bundled.rotationWeeks)]
        json["stations"] = stations
        let matchingCache = try LunchMenuParser.parse(JSONSerialization.data(withJSONObject: json))
        switch changedSetting {
        case "validFrom": json["validFrom"] = "2026-08-11"
        case "validTo": json["validTo"] = "2027-05-27"
        case "semesterSwitch": json["semesterSwitch"] = "2027-01-12"
        case "offset": json["offset"] = 1
        case "previousYear":
            json["validFrom"] = "2025-08-12"
            json["validTo"] = "2026-05-29"
            json["semesterSwitch"] = "2026-01-06"
        default: break
        }
        let cached = try JSONSerialization.data(withJSONObject: json)
        // Each cache is valid on its own; only its saved settings decide whether it is reusable.
        _ = try LunchMenuParser.parse(cached)
        let expected = changedSetting == "matching" ? matchingCache : bundled
        let loaded = try #require(LunchMenuLoader.load(cachedData: cached))
        #expect(LunchMenuLoader.loadWithSource(cachedData: cached).isBundled == (changedSetting != "matching"))
        #expect(loaded == expected)
        #expect(loaded.menu(for: today) == expected.menu(for: today))
        #expect(loaded.menu(for: bundled.validTo.advanced(by: 1)) == nil)

        // Widgets make the same cache decision without opening or refreshing the app.
        let entries = LunchWidgetTimelinePlanner.entries(from: today.date()!, cachedData: cached,
                                                          inputs: ResolverInputs(catalog: TestSupport.catalog))
        #expect(entries.first?.menu == expected.menu(for: today))
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
