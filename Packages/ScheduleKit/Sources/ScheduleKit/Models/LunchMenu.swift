import Foundation

public enum LunchMenuStation: String, CaseIterable, Hashable, Sendable {
    case comfort
    case mindful
    case sides
    case soup
    case international
    case special
}

public struct LunchMenuSection: Identifiable, Equatable, Sendable {
    public let station: LunchMenuStation
    public let items: [String]

    public var id: LunchMenuStation { station }

    public init(station: LunchMenuStation, items: [String]) {
        self.station = station
        self.items = items
    }
}

public struct LunchMenuDay: Equatable, Sendable {
    public let day: DayKey
    public let sections: [LunchMenuSection]

    public init(day: DayKey, sections: [LunchMenuSection]) {
        self.day = day
        self.sections = sections
    }
}

/// A validated lunch rotation, assembled from the per-station files the
/// website publishes under `src/data/lunch-rotating` plus the rotation dates
/// the bundled manifest carries.
public struct LunchMenu: Equatable, Sendable {
    struct RotationSettings: Equatable, Sendable {
        let validFrom: DayKey
        let validTo: DayKey
        let semesterSwitch: DayKey
        let offset: Int
    }

    /// Bundled settings that must agree before reusing cached station data.
    let rotationSettings: RotationSettings
    public var validFrom: DayKey { rotationSettings.validFrom }
    public var validTo: DayKey { rotationSettings.validTo }
    public var semesterSwitch: DayKey { rotationSettings.semesterSwitch }
    public var offset: Int { rotationSettings.offset }
    /// How many weeks the rotation runs before repeating. Read from the
    /// published station data, which has already changed from four to five.
    public let rotationWeeks: Int

    let comfort: StationSchedule<String>
    let mindful: StationSchedule<String>
    let sides: StationSchedule<[String]>
    let soup: StationSchedule<[String]>
    let international: StationSchedule<String>
    let special: [[String]]

    /// Resolves a weekday using the same date math as the website. Returns nil
    /// for weekends, dates outside the advertised range, or days without dishes.
    public func menu(for day: DayKey) -> LunchMenuDay? {
        guard validFrom <= day, day <= validTo,
              let weekday = day.weekday(), (2...6).contains(weekday),
              let start = validFrom.date(), let target = day.date(),
              let elapsedDays = SchoolTime.calendar.dateComponents(
                [.day], from: start, to: target).day else { return nil }

        // A partial opening week still advances on the following Monday.
        let startWeekday = SchoolTime.calendar.component(.weekday, from: start)
        let daysFromMonday = (startWeekday + 5) % 7
        let week = ((elapsedDays + daysFromMonday) / 7 + offset) % rotationWeeks
        let weekdayIndex = weekday - 2 // Monday = 0, Friday = 4
        let semester = day < semesterSwitch ? 0 : 1
        let weekdayName = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"][weekdayIndex]

        let sections = [
            LunchMenuSection(station: .comfort,
                             items: [comfort.value(week: week, weekday: weekdayIndex)]),
            LunchMenuSection(station: .mindful,
                             items: [mindful.value(week: week, weekday: weekdayIndex)]),
            LunchMenuSection(station: .sides,
                             items: sides.value(week: week, weekday: weekdayIndex)),
            LunchMenuSection(station: .soup,
                             items: soup.value(week: week, weekday: weekdayIndex)),
            LunchMenuSection(station: .international,
                             items: [international.value(week: week, weekday: weekdayIndex)]),
            LunchMenuSection(station: .special,
                             items: [special[semester][weekdayIndex] + " " + weekdayName]),
        ]

        // The website fills slots the kitchen hasn't planned with placeholders
        // such as "?? No Information". Leave those stations off the day rather
        // than listing the placeholder as a dish.
        let availableSections = sections.compactMap { section -> LunchMenuSection? in
            let items = section.items
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !Self.isPlaceholder($0) }
            return items.isEmpty ? nil : LunchMenuSection(station: section.station, items: items)
        }
        guard !availableSections.isEmpty else { return nil }
        return LunchMenuDay(day: day, sections: availableSections)
    }

    private static func isPlaceholder(_ item: String) -> Bool {
        item.hasPrefix("??")
    }
}

struct StationSchedule<Value: Equatable & Sendable>: Equatable, Sendable {
    enum Storage: Equatable, Sendable {
        case weekly([Value])
        case daily([[Value]])
    }

    let storage: Storage

    func value(week: Int, weekday: Int) -> Value {
        switch storage {
        case .weekly(let values): return values[week]
        case .daily(let values): return values[week][weekday]
        }
    }
}
