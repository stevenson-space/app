import Foundation
import Testing
@testable import StudentIDKit

@Suite struct Code39Tests {

    @Test func moduleCountMatchesTheSymbologyFormula() throws {
        // 15 modules per character, one-module gaps, two sentinels: 16n + 31.
        for payload in ["1234", "59435", "123456", "12345678"] {
            let symbol = try Code39.encode(payload)
            #expect(symbol.moduleCount == 16 * payload.count + 31)
            #expect(symbol.totalModuleCount == symbol.moduleCount + 20)
        }
    }

    @Test func symbolStartsAndEndsWithTheSentinelBarPattern() throws {
        let symbol = try Code39.encode("59435")
        // '*' is narrow bar, wide space, narrow bar, narrow space, wide bar…
        #expect(Array(symbol.modules.prefix(4)) == [true, false, false, false])
        #expect(symbol.modules.first == true)
        #expect(symbol.modules.last == true)
    }

    @Test func everyCharacterUsesNineElementsWithThreeWide() {
        // The structural invariant of the symbology. A typo anywhere in the
        // table breaks one of these three counts.
        for (character, pattern) in Code39.patternTable {
            #expect(pattern.count == 9, "\(character) has \(pattern.count) elements")
            #expect(pattern.filter { $0 }.count == 3, "\(character) has the wrong wide-element count")

            let bars = pattern.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
            let spaces = pattern.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)
            #expect(bars.count == 5)
            #expect(spaces.count == 4)

            let wideBars = bars.filter { $0 }.count
            let wideSpaces = spaces.filter { $0 }.count
            // Alphanumerics carry two wide bars and one wide space; the four
            // punctuation characters carry three wide spaces and no wide bar.
            #expect((wideBars == 2 && wideSpaces == 1) || (wideBars == 0 && wideSpaces == 3),
                    "\(character) is in neither valid family")
        }
    }

    @Test func tableCoversTheFullAlphabetWithoutDuplicates() {
        #expect(Code39.patternTable.count == 44)   // 43 data characters plus '*'
        #expect(Code39.values.count == 43)
        for value in Code39.values {
            #expect(Code39.patternTable[value] != nil, "\(value) is missing a pattern")
        }
        let distinct = Set(Code39.patternTable.values.map { $0.map { $0 ? "1" : "0" }.joined() })
        #expect(distinct.count == Code39.patternTable.count, "two characters share a pattern")
    }

    @Test func barsAndSpacesAlternateAtCharacterBoundaries() throws {
        let symbol = try Code39.encode("59435")
        // Every character begins and ends on a bar, so a run of white between
        // characters is exactly the narrow gap plus the character's last space.
        var whiteRun = 0
        var longestWhiteRun = 0
        for module in symbol.modules {
            whiteRun = module ? 0 : whiteRun + 1
            longestWhiteRun = max(longestWhiteRun, whiteRun)
        }
        // Worst case: a wide trailing space (3) plus the inter-character gap (1).
        #expect(longestWhiteRun <= 4)
    }

    @Test func rejectsCharactersTheSymbologyCannotCarry() {
        #expect(throws: Code39.EncodingError.unsupportedCharacter("!")) {
            try Code39.encode("59!35")
        }
        #expect(throws: Code39.EncodingError.empty) {
            try Code39.encode("")
        }
    }

    @Test func uppercasesLettersRatherThanRejectingThem() throws {
        let lower = try Code39.encode("ab12")
        let upper = try Code39.encode("AB12")
        #expect(lower.modules == upper.modules)
        #expect(lower.payload == "AB12")
    }

    @Test func computesTheModuloFortyThreeCheckDigit() throws {
        // "59435" -> 5+9+4+3+5 = 26 -> values[26] == "Q"
        #expect(try Code39.checkDigit(for: "59435") == "Q")
        #expect(try Code39.checkDigit(for: "0") == "0")
        // A check digit adds one character, and one character is 16 modules.
        let plain = try Code39.encode("59435")
        let checked = try Code39.encode("59435", appendCheckDigit: true)
        #expect(checked.moduleCount == plain.moduleCount + 16)
    }
}
