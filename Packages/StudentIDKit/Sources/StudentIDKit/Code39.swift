import Foundation

/// Code 39 (a.k.a. "3 of 9") encoder.
///
/// The school's Infinite Campus barcode is Code 39, so recreating it means
/// re-encoding the decoded payload into the *same* symbol a scanner already
/// accepts — not approximating it. Everything here is pure integer/table work so
/// it can be exercised on the host with `swift test`.
///
/// Structure of the symbology: every character is 9 elements — 5 bars and 4
/// spaces, alternating, starting and ending with a bar — of which exactly 3 are
/// wide. With the standard 3:1 wide:narrow ratio a character occupies
/// `3 * 3 + 6 * 1 = 15` modules, and characters are separated by a one-module
/// space. A payload of `n` characters, wrapped in the `*` start/stop sentinels,
/// is therefore `15 * (n + 2) + (n + 1) = 16n + 31` modules wide.
public enum Code39 {

    /// An encoded symbol, expanded to equal-width modules.
    public struct Symbol: Equatable, Sendable {
        /// The text a scanner reads back — the sentinels are not included, since
        /// scanners strip them.
        public let payload: String
        /// One entry per module, in drawing order: `true` is a bar, `false` a space.
        public let modules: [Bool]

        public var moduleCount: Int { modules.count }

        /// Module count including the mandatory quiet zone on each side. This is
        /// the number to lay out against the available width — forgetting the
        /// quiet zones is what makes a barcode unscannable at the edges.
        public var totalModuleCount: Int { modules.count + 2 * Code39.quietZoneModules }

        /// Contiguous bars in module coordinates, excluding the quiet zones.
        /// Drawing each run once avoids seams between adjacent bar modules.
        public var barRuns: [Range<Int>] {
            var runs: [Range<Int>] = []
            var index = 0
            while index < modules.count {
                guard modules[index] else {
                    index += 1
                    continue
                }
                let start = index
                while index < modules.count, modules[index] { index += 1 }
                runs.append(start..<index)
            }
            return runs
        }
    }

    public enum EncodingError: Error, Equatable, CustomStringConvertible {
        case empty
        case unsupportedCharacter(Character)

        public var description: String {
            switch self {
            case .empty:
                return "nothing to encode"
            case .unsupportedCharacter(let character):
                return "Code 39 cannot encode \"\(character)\""
            }
        }
    }

    /// The spec calls for a quiet zone of at least 10 narrow elements.
    public static let quietZoneModules = 10

    /// Wide elements are three modules; narrow elements are one.
    public static let wideModules = 3
    public static let narrowModules = 1

    // MARK: - Encoding

    /// Encodes `text` between `*` sentinels.
    ///
    /// - Parameter appendCheckDigit: appends the modulo-43 check character. Only
    ///   needed when the source symbol carried one (Vision reports that as a
    ///   `code39Checksum` symbology and strips the digit from the payload), because
    ///   re-encoding without it would produce a different symbol than the one the
    ///   school issued.
    public static func encode(_ text: String, appendCheckDigit: Bool = false) throws -> Symbol {
        let payload = text.uppercased()
        guard !payload.isEmpty else { throw EncodingError.empty }

        var body = payload
        if appendCheckDigit {
            body.append(try checkDigit(for: payload))
        }

        var modules: [Bool] = []
        modules.reserveCapacity(16 * body.count + 31)

        let characters = Array("*" + body + "*")
        for (index, character) in characters.enumerated() {
            guard let pattern = patterns[character] else {
                throw EncodingError.unsupportedCharacter(character)
            }
            // Elements alternate bar, space, bar, … and always start with a bar.
            for (element, isWide) in pattern.enumerated() {
                let isBar = element.isMultiple(of: 2)
                let width = isWide ? wideModules : narrowModules
                modules.append(contentsOf: repeatElement(isBar, count: width))
            }
            // One narrow space between characters, none after the last.
            if index < characters.count - 1 {
                modules.append(false)
            }
        }

        return Symbol(payload: payload, modules: modules)
    }

    /// The modulo-43 check character defined by the symbology.
    public static func checkDigit(for text: String) throws -> Character {
        var sum = 0
        for character in text.uppercased() {
            guard let value = values.firstIndex(of: character) else {
                throw EncodingError.unsupportedCharacter(character)
            }
            sum += value
        }
        return values[sum % values.count]
    }

    /// Every character this symbology can carry, in check-digit value order.
    public static let values: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%")

    // MARK: - Pattern table

    /// Nine elements per character (bar, space, bar, … bar); `true` is wide.
    ///
    /// The table is systematic, which is what the tests assert: the 40
    /// alphanumeric characters plus `*` each use two wide bars and one wide
    /// space, cycling the ten two-of-five bar patterns across the four
    /// space positions; the four punctuation characters use three wide spaces
    /// and no wide bar.
    private static let patterns: [Character: [Bool]] = {
        let table: [(Character, String)] = [
            ("1", "100100001"), ("2", "001100001"), ("3", "101100000"),
            ("4", "000110001"), ("5", "100110000"), ("6", "001110000"),
            ("7", "000100101"), ("8", "100100100"), ("9", "001100100"),
            ("0", "000110100"),
            ("A", "100001001"), ("B", "001001001"), ("C", "101001000"),
            ("D", "000011001"), ("E", "100011000"), ("F", "001011000"),
            ("G", "000001101"), ("H", "100001100"), ("I", "001001100"),
            ("J", "000011100"),
            ("K", "100000011"), ("L", "001000011"), ("M", "101000010"),
            ("N", "000010011"), ("O", "100010010"), ("P", "001010010"),
            ("Q", "000000111"), ("R", "100000110"), ("S", "001000110"),
            ("T", "000010110"),
            ("U", "110000001"), ("V", "011000001"), ("W", "111000000"),
            ("X", "010010001"), ("Y", "110010000"), ("Z", "011010000"),
            ("-", "010000101"), (".", "110000100"), (" ", "011000100"),
            ("$", "010101000"), ("/", "010100010"), ("+", "010001010"),
            ("%", "000101010"),
            ("*", "010010100"),
        ]
        return Dictionary(uniqueKeysWithValues: table.map { ($0.0, $0.1.map { $0 == "1" }) })
    }()

    /// Exposed for the table-integrity tests.
    static var patternTable: [Character: [Bool]] { patterns }

    /// The character a nine-element wide/narrow pattern stands for, if any.
    /// The reverse of the drawing table, used when reading a symbol back.
    static func character(for pattern: [Bool]) -> Character? {
        reversePatterns[pattern.map { $0 ? "1" : "0" }.joined()]
    }

    private static let reversePatterns: [String: Character] = Dictionary(
        uniqueKeysWithValues: patterns.map { ($0.value.map { $0 ? "1" : "0" }.joined(), $0.key) })
}
