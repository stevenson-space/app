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

/// The menus the website's API has published: one per school day in a window
/// that runs from about a week behind the last refresh to three weeks ahead.
/// The website works out its own rotation, so the app only looks days up.
public struct LunchMenu: Equatable, Sendable {
    private let days: [DayKey: LunchMenuDay]

    init(days: [LunchMenuDay]) {
        self.days = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Nil for any date without a published menu: a weekend, a day off, or a
    /// day outside the window.
    public func menu(for day: DayKey) -> LunchMenuDay? { days[day] }

    /// The last day with a published menu, or nil when there are none (over
    /// the summer, the window is empty).
    public var lastDay: DayKey? { days.keys.max() }
}
