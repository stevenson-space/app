import Foundation

/// An inclusive range of calendar dates.
public struct DateSpan: Hashable, Codable, Sendable {
    public var start: DayKey
    public var end: DayKey

    public init(start: DayKey, end: DayKey) {
        self.start = start
        self.end = end
    }

    public init(single day: DayKey) {
        self.init(start: day, end: day)
    }

    public var isSingleDay: Bool { start == end }

    public func contains(_ day: DayKey) -> Bool {
        start <= day && day <= end
    }

    /// Every day in the span, in order. Spans are at most school-year sized;
    /// a hard bound guards against corrupt data.
    public func days(calendar: Calendar = SchoolTime.calendar, limit: Int = 400) -> [DayKey] {
        var result: [DayKey] = []
        var current = start
        while current <= end && result.count < limit {
            result.append(current)
            current = current.advanced(by: 1, calendar: calendar)
        }
        return result
    }
}

public struct SchoolBreak: Hashable, Sendable {
    public let span: DateSpan
    public let label: String

    public init(span: DateSpan, label: String) {
        self.span = span
        self.label = label
    }
}

/// Bundled school-year boundaries. Deliberately in the app, not the remote JSON:
/// outside these bounds the app never defaults to Standard.
public struct SchoolYear: Hashable, Sendable {
    public let name: String
    public let firstDay: DayKey
    public let lastDay: DayKey
    public let breaks: [SchoolBreak]
    /// Special annotations for in-session days (e.g. Freshman Orientation).
    public let labeledDays: [DayKey: String]

    public init(name: String, firstDay: DayKey, lastDay: DayKey,
                breaks: [SchoolBreak], labeledDays: [DayKey: String] = [:]) {
        self.name = name
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.breaks = breaks
        self.labeledDays = labeledDays
    }

    public func contains(_ day: DayKey) -> Bool {
        firstDay <= day && day <= lastDay
    }

    public func breakContaining(_ day: DayKey) -> SchoolBreak? {
        breaks.first { $0.span.contains(day) }
    }
}

public enum SchoolYearCatalog {
    /// Append future years here (requires an app update, by design).
    public static let years: [SchoolYear] = [year2026_27]

    public static let year2026_27 = SchoolYear(
        name: "2026–27",
        firstDay: DayKey(year: 2026, month: 8, day: 12),
        lastDay: DayKey(year: 2027, month: 5, day: 26),
        breaks: [
            SchoolBreak(
                span: DateSpan(start: DayKey(year: 2026, month: 12, day: 21),
                               end: DayKey(year: 2027, month: 1, day: 6)),
                label: "Winter Break"),
            SchoolBreak(
                span: DateSpan(start: DayKey(year: 2027, month: 3, day: 22),
                               end: DayKey(year: 2027, month: 3, day: 26)),
                label: "Spring Break"),
        ],
        labeledDays: [
            DayKey(year: 2026, month: 8, day: 12): "Freshman Orientation"
        ]
    )

    public static func year(containing day: DayKey) -> SchoolYear? {
        years.first { $0.contains(day) }
    }

    /// The first day of the next school year strictly after the given date,
    /// if a bundled year exists for it.
    public static func nextYearStart(after day: DayKey) -> DayKey? {
        years.map(\.firstDay).filter { $0 > day }.min()
    }
}
