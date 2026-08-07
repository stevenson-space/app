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

    /// Compact textual snapshot of a timeline for readable assertions:
    /// "08:30-08:54 4A lunch Lunch"
    static func lines(_ timeline: DayTimeline) -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = SchoolTime.timeZone
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
