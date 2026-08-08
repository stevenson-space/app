import Foundation

/// What a remote-map key semantically means.
public enum DayTypeFamily: Hashable, Sendable {
    case bell(BellFamily)
    case noSchool
    case asynchronous
    case unknown(rawKey: String)

    /// Precedence when one date appears under multiple keys (lower wins).
    public var precedenceRank: Int {
        switch self {
        case .noSchool: return 0
        case .asynchronous: return 1
        case .bell(.earlyDismissal): return 2
        case .bell: return 3
        case .unknown: return 4
        }
    }
}

/// The parsed remote day-type map. Exception-based: unlisted in-session
/// weekdays are Standard by design and never appear here.
public struct DayTypeMap: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let rawKey: String
        public let family: DayTypeFamily
        public let span: DateSpan

        public init(rawKey: String, family: DayTypeFamily, span: DateSpan) {
            self.rawKey = rawKey
            self.family = family
            self.span = span
        }
    }

    public struct Match: Equatable, Sendable {
        public let rawKey: String
        public let family: DayTypeFamily
        public let span: DateSpan
        /// The date appeared under more than one key; precedence decided.
        public let hadConflict: Bool
    }

    public let entries: [Entry]
    public let warnings: [String]

    public init(entries: [Entry], warnings: [String] = []) {
        self.entries = entries
        self.warnings = warnings
    }

    public func match(_ day: DayKey) -> Match? {
        let hits = entries.enumerated().filter { $0.element.span.contains(day) }
        guard let best = hits.min(by: {
            ($0.element.family.precedenceRank, $0.offset) < ($1.element.family.precedenceRank, $1.offset)
        }) else { return nil }
        return Match(rawKey: best.element.rawKey,
                     family: best.element.family,
                     span: best.element.span,
                     hadConflict: hits.count > 1)
    }

    /// The overall date range the file speaks for.
    public var coverage: DateSpan? {
        guard let minStart = entries.map(\.span.start).min(),
              let maxEnd = entries.map(\.span.end).max() else { return nil }
        return DateSpan(start: minStart, end: maxEnd)
    }
}

public enum ParserError: Error, Equatable, CustomStringConvertible {
    case tooLarge(bytes: Int)
    case notAnObject
    case noValidEntries

    public var description: String {
        switch self {
        case .tooLarge(let bytes): return "file too large (\(bytes) bytes)"
        case .notAnObject: return "top level is not a JSON object of string arrays"
        case .noValidEntries: return "no valid date entries found"
        }
    }
}

/// Parses `schedule-dates.json`: `{"Late Arrival": ["8/21/2025", "12/18/2025-12/19/2025", …], …}`.
/// M/D/YYYY, no leading zeros, ranges via "start-end". Malformed individual
/// entries are skipped with warnings; a non-conforming file fails wholesale so
/// the caller keeps its last-good cache.
public enum ScheduleDatesParser {
    public static let maxBytes = 262_144

    public static func parse(_ data: Data, calendar: Calendar = SchoolTime.calendar) throws -> DayTypeMap {
        guard data.count <= maxBytes else { throw ParserError.tooLarge(bytes: data.count) }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else { throw ParserError.notAnObject }

        var entries: [DayTypeMap.Entry] = []
        var warnings: [String] = []

        for key in dict.keys.sorted() {
            guard let list = dict[key] as? [String] else {
                warnings.append("'\(key)' is not an array of strings; skipped")
                continue
            }
            let family = family(forKey: key)
            for raw in list {
                if let span = parseSpan(raw) {
                    entries.append(.init(rawKey: key, family: family, span: span))
                } else {
                    warnings.append("unparseable date '\(raw)' under '\(key)'; skipped")
                }
            }
        }

        guard !entries.isEmpty else { throw ParserError.noValidEntries }
        entries.sort { ($0.span.start, $0.family.precedenceRank) < ($1.span.start, $1.family.precedenceRank) }
        return DayTypeMap(entries: entries, warnings: warnings)
    }

    /// Case-insensitive, whitespace-tolerant key registry. Unknown keys are
    /// preserved so future types degrade to an honest "no details" state.
    public static func family(forKey rawKey: String) -> DayTypeFamily {
        let normalized = rawKey
            .lowercased()
            .replacingOccurrences(of: "—", with: "-")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        switch normalized {
        case "standard", "standard schedule":
            return .bell(.standard)
        case "late arrival":
            return .bell(.lateArrival)
        case "odyssey":
            return .bell(.odyssey)
        case "activity period":
            return .bell(.activityPeriod)
        case "pm assembly", "pm assembly schedule":
            return .bell(.pmAssembly)
        case "early dismissal":
            return .bell(.earlyDismissal)
        case "summer", "summer school", "summer schedule":
            return .bell(.summer)
        case "no school", "non-attendance day", "no school - weekend":
            return .noSchool
        case "asynchronous", "async", "e-learning", "elearning",
             "asynchronous e-learning", "asynchronous e-learning day":
            return .asynchronous
        default:
            return .unknown(rawKey: rawKey.trimmingCharacters(in: .whitespaces))
        }
    }

    // MARK: - Date parsing

    static func parseSpan(_ raw: String) -> DateSpan? {
        // Dates contain "/" only, so "-" safely separates range endpoints. Fold
        // en/em dashes to the ASCII hyphen first so a "12/18–12/19" range splits.
        let normalized = raw
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        let parts = normalized.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        switch parts.count {
        case 1:
            guard let day = parseDay(parts[0]) else { return nil }
            return DateSpan(single: day)
        case 2:
            guard let start = parseDay(parts[0]), let end = parseDay(parts[1]), start <= end else { return nil }
            return DateSpan(start: start, end: end)
        default:
            return nil
        }
    }

    static func parseDay(_ raw: String) -> DayKey? {
        let components = raw.split(separator: "/")
        guard components.count == 3,
              let month = Int(components[0]),
              let day = Int(components[1]),
              let year = Int(components[2]),
              (1...12).contains(month), (1...31).contains(day), (2000...2100).contains(year) else {
            return nil
        }
        let key = DayKey(year: year, month: month, day: day)
        return key.isValid ? key : nil
    }
}
