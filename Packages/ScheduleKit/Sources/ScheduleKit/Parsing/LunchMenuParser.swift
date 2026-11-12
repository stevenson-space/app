import Foundation

public enum LunchMenuParserError: Error, Equatable, CustomStringConvertible {
    case tooLarge(bytes: Int)
    case invalid(String)

    public var description: String {
        switch self {
        case .tooLarge(let bytes): return "file too large (\(bytes) bytes)"
        case .invalid(let message): return message
        }
    }
}

/// Parses the API's `lunch.json`:
/// `{"days": [{"date": "2026-11-02", "menu": {"comfort": "…", "sides": ["…", "…"], …}}, …]}`.
/// A payload that does not conform fails wholesale so the caller keeps its
/// last-good cache. An empty `days` is valid: it is what the API serves when
/// no menus fall inside its window, as over the summer.
public enum LunchMenuParser {
    public static let maxBytes = 65_536

    public static func parse(_ data: Data) throws -> LunchMenu {
        guard data.count <= maxBytes else {
            throw LunchMenuParserError.tooLarge(bytes: data.count)
        }

        let wire: WirePayload
        do {
            wire = try JSONDecoder().decode(WirePayload.self, from: data)
        } catch {
            throw LunchMenuParserError.invalid("invalid lunch-menu JSON: \(error.localizedDescription)")
        }
        return LunchMenu(days: try wire.days.compactMap(menuDay))
    }

    /// Nil when the kitchen has planned nothing for the day.
    private static func menuDay(_ wire: WireDay) throws -> LunchMenuDay? {
        let day = try parseDay(wire.date)
        let weekdayName = day.weekday().map { weekdayNames[$0 - 1] }

        let sections = LunchMenuStation.allCases.compactMap { station -> LunchMenuSection? in
            // The API passes on the placeholders the kitchen's data uses for
            // slots it hasn't planned, such as "?? No Information" (older
            // menus used "None Specified"). Leave those stations off the day
            // rather than listing the placeholder as a dish.
            let items = (wire.menu.items[station] ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !isPlaceholder($0) }
                // The special repeats by weekday and the website names it
                // that way: "Tacos Tuesday".
                .map { station == .special ? [$0, weekdayName].compactMap { $0 }.joined(separator: " ") : $0 }
            return items.isEmpty ? nil : LunchMenuSection(station: station, items: items)
        }
        return sections.isEmpty ? nil : LunchMenuDay(day: day, sections: sections)
    }

    /// Indexed by `DayKey.weekday()`, where 1 is Sunday.
    private static let weekdayNames = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    private static func isPlaceholder(_ item: String) -> Bool {
        item.hasPrefix("??") || ["no information", "none specified", "tbd"].contains(item.lowercased())
    }

    private static func parseDay(_ raw: String) throws -> DayKey {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            throw LunchMenuParserError.invalid("date '\(raw)' must use YYYY-MM-DD")
        }
        let key = DayKey(year: year, month: month, day: day)
        guard key.isValid else {
            throw LunchMenuParserError.invalid("date '\(raw)' is not a valid date")
        }
        return key
    }
}

private struct WirePayload: Decodable {
    let days: [WireDay]
}

private struct WireDay: Decodable {
    let date: String
    let menu: WireMenu
}

/// Reads the stations the app knows and ignores any others, so the API can add
/// one without failing every install that predates it.
private struct WireMenu: Decodable {
    var items: [LunchMenuStation: [String]] = [:]

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        for station in LunchMenuStation.allCases {
            let key = Key(stringValue: station.rawValue)
            // A station serves one dish or a list of them, and which it is
            // belongs to the kitchen's data, not to the station.
            if let dishes = try? container.decode([String].self, forKey: key) {
                items[station] = dishes
            } else if let dish = try container.decodeIfPresent(String.self, forKey: key) {
                items[station] = [dish]
            }
        }
    }
}
