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

/// A validated four-week lunch rotation. The source format matches the
/// website's `src/data/lunch-menu.json` manifest exactly.
public struct LunchMenu: Equatable, Sendable {
    public let validFrom: DayKey
    public let validTo: DayKey
    public let semesterSwitch: DayKey
    public let offset: Int

    let comfort: StationSchedule<String>
    let mindful: StationSchedule<String>
    let sides: StationSchedule<[String]>
    let soup: StationSchedule<[String]>
    let international: StationSchedule<String>
    let special: [[String]]

    /// Resolves a weekday using the same date math as the website. Returns nil
    /// for weekends or dates outside the manifest's advertised range.
    public func menu(for day: DayKey) -> LunchMenuDay? {
        guard validFrom <= day, day <= validTo,
              let weekday = day.weekday(), (2...6).contains(weekday),
              let start = validFrom.date(), let target = day.date(),
              let elapsedDays = SchoolTime.calendar.dateComponents(
                [.day], from: start, to: target).day else { return nil }

        let week = (elapsedDays / 7 + offset) % 4
        let weekdayIndex = weekday - 2 // Monday = 0, Friday = 4
        let semester = day < semesterSwitch ? 0 : 1
        let weekdayName = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"][weekdayIndex]

        return LunchMenuDay(day: day, sections: [
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
        ])
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
