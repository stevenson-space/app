import Foundation
import Testing
@testable import ScheduleKit

enum TestSupport {
    static let catalog: BellScheduleCatalog = {
        do {
            return try BellScheduleCatalog.loadBundled()
        } catch {
            fatalError("bundled catalog failed to load: \(error)")
        }
    }()

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func map(_ json: String) throws -> DayTypeMap {
        try ScheduleDatesParser.parse(Data(json.utf8))
    }

    static func inputs(map: DayTypeMap? = nil,
                       overrides: [DayKey: DayOverride] = [:],
                       config: UserConfig = UserConfig()) -> ResolverInputs {
        ResolverInputs(map: map, overrides: overrides, config: config,
                       catalog: catalog, years: SchoolYearCatalog.years)
    }

    /// A `lunch.json` response in the API's shape, with a menu for each
    /// weekday from `start` through `end`. Dishes are named after their date
    /// and `seed`, so a test can tell one day or one publication from another.
    static func lunchPayload(from start: DayKey, through end: DayKey, seed: String = "a",
                             generatedAt: String = "2026-09-14T07:44:09.498Z") -> Data {
        var days: [(DayKey, [String: Any])] = []
        var candidate = start
        while candidate <= end {
            if !candidate.isWeekend { days.append((candidate, lunchDishes(candidate, seed: seed))) }
            candidate = candidate.advanced(by: 1)
        }
        return lunchPayload(days: days, generatedAt: generatedAt)
    }

    static func lunchPayload(days: [(DayKey, [String: Any])],
                             generatedAt: String = "2026-09-14T07:44:09.498Z") -> Data {
        let object: [String: Any] = [
            "version": 1,
            "generatedAt": generatedAt,
            "signature": "121fea1d",
            "validRange": ["start": "2026-08-10", "end": "2027-05-31"],
            "days": days.map { ["date": $0.0.description, "menu": $0.1] },
        ]
        return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func lunchDishes(_ day: DayKey, seed: String = "a") -> [String: Any] {
        [
            "comfort": "\(seed)-comfort-\(day)",
            "mindful": "\(seed)-mindful-\(day)",
            "sides": ["\(seed)-sides-\(day)-a", "\(seed)-sides-\(day)-b"],
            "soup": ["\(seed)-soup-\(day)-a", "\(seed)-soup-\(day)-b"],
            "international": "\(seed)-international-\(day)",
            "special": "\(seed)-special",
        ]
    }

    /// Four school weeks of menus around mid-September 2026.
    static let septemberLunchPayload = lunchPayload(from: day(2026, 9, 7), through: day(2026, 10, 2))
    static let septemberLunchMenu: LunchMenu = {
        do {
            return try LunchMenuParser.parse(septemberLunchPayload)
        } catch {
            fatalError("test lunch payload failed to parse: \(error)")
        }
    }()

    /// Compact textual snapshot of a timeline for readable assertions:
    /// "08:30-08:54 4A lunch Lunch"
    static func lines(_ timeline: DayTimeline) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = SchoolTime.timeZone
        formatter.dateFormat = "HH:mm"
        return timeline.blocks.map { block in
            "\(formatter.string(from: block.start))-\(formatter.string(from: block.end)) " +
            "\(block.id) \(block.role.rawValue) \(block.displayName)"
        }
    }

    /// Instant on a given day at wall-clock H:mm(:ss) in Chicago.
    static func at(_ day: DayKey, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        day.date(at: HourMinute(hour: hour, minute: minute))!.addingTimeInterval(TimeInterval(second))
    }
}

func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> DayKey {
    DayKey(year: year, month: month, day: dayOfMonth)
}
