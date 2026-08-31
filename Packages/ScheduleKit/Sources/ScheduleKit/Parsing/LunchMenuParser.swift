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

public enum LunchMenuParser {
    public static let maxBytes = 65_536

    public static func parse(_ data: Data) throws -> LunchMenu {
        guard data.count <= maxBytes else {
            throw LunchMenuParserError.tooLarge(bytes: data.count)
        }

        let wire: WireManifest
        do {
            wire = try JSONDecoder().decode(WireManifest.self, from: data)
        } catch {
            throw LunchMenuParserError.invalid("invalid lunch-menu JSON: \(error.localizedDescription)")
        }

        let validFrom = try parseDay(wire.validFrom, field: "validFrom")
        let validTo = try parseDay(wire.validTo, field: "validTo")
        let semesterSwitch = try parseDay(wire.semesterSwitch, field: "semesterSwitch")
        guard validFrom < validTo else {
            throw LunchMenuParserError.invalid("validFrom must be before validTo")
        }
        guard validFrom <= semesterSwitch, semesterSwitch <= validTo else {
            throw LunchMenuParserError.invalid("semesterSwitch must be inside the valid range")
        }
        guard (0..<4).contains(wire.offset) else {
            throw LunchMenuParserError.invalid("offset must be in 0..<4")
        }

        let comfort = try station(wire.stations.comfort, name: "comfort", validate: nonempty)
        let mindful = try station(wire.stations.mindful, name: "mindful", validate: nonempty)
        let sides = try station(wire.stations.sides, name: "sides", validate: pair)
        let soup = try station(wire.stations.soup, name: "soup", validate: pair)
        let international = try station(
            wire.stations.international, name: "international", validate: nonempty)
        guard wire.special.count == 2,
              wire.special.allSatisfy({ $0.count == 5 && $0.allSatisfy(nonempty) }) else {
            throw LunchMenuParserError.invalid("special must contain two semesters of five weekdays")
        }

        return LunchMenu(
            validFrom: validFrom,
            validTo: validTo,
            semesterSwitch: semesterSwitch,
            offset: wire.offset,
            comfort: comfort,
            mindful: mindful,
            sides: sides,
            soup: soup,
            international: international,
            special: wire.special)
    }

    public static func loadBundled() throws -> LunchMenu {
        try parse(bundledData())
    }

    static func bundledData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "lunch-menu", withExtension: "json") else {
            throw LunchMenuParserError.invalid("bundled lunch-menu.json is missing")
        }
        return try Data(contentsOf: url)
    }

    private static func parseDay(_ raw: String, field: String) throws -> DayKey {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            throw LunchMenuParserError.invalid("\(field) must use YYYY-MM-DD")
        }
        let key = DayKey(year: year, month: month, day: day)
        guard key.isValid else {
            throw LunchMenuParserError.invalid("\(field) is not a valid date")
        }
        return key
    }

    private static func station<Value: Decodable & Equatable & Sendable>(
        _ wire: WireStation<Value>, name: String, validate: (Value) -> Bool
    ) throws -> StationSchedule<Value> {
        switch wire.values {
        case .weekly(let values):
            guard values.count == 4, values.allSatisfy(validate) else {
                throw LunchMenuParserError.invalid("\(name) weekly data must contain four valid entries")
            }
            return StationSchedule(storage: .weekly(values))
        case .daily(let values):
            guard values.count == 4,
                  values.allSatisfy({ $0.count == 5 && $0.allSatisfy(validate) }) else {
                throw LunchMenuParserError.invalid(
                    "\(name) daily data must contain four weeks of five valid weekdays")
            }
            return StationSchedule(storage: .daily(values))
        }
    }

    private static func nonempty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func pair(_ value: [String]) -> Bool {
        value.count == 2 && value.allSatisfy(nonempty)
    }
}

private struct WireManifest: Decodable {
    let validFrom: String
    let validTo: String
    let semesterSwitch: String
    let offset: Int
    let stations: WireStations
    let special: [[String]]
}

private struct WireStations: Decodable {
    let comfort: WireStation<String>
    let mindful: WireStation<String>
    let sides: WireStation<[String]>
    let soup: WireStation<[String]>
    let international: WireStation<String>
}

private struct WireStation<Value: Decodable>: Decodable {
    enum Values {
        case weekly([Value])
        case daily([[Value]])
    }

    let values: Values

    private enum CodingKeys: String, CodingKey {
        case cadence, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .cadence) {
        case "weekly": values = .weekly(try container.decode([Value].self, forKey: .data))
        case "daily": values = .daily(try container.decode([[Value]].self, forKey: .data))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .cadence, in: container, debugDescription: "cadence must be weekly or daily")
        }
    }
}
