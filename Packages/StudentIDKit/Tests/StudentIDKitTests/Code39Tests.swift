import Foundation
import Testing
@testable import StudentIDKit

@Suite struct Code39Tests {
    @Test func fiveDigitStudentNumberHasExpectedSizeAndQuietZones() throws {
        let symbol = try Code39Encoder.encode("12345")

        #expect(symbol.payload == "12345")
        #expect(symbol.totalModules == 131)
        #expect(symbol.runs.first == Code39Run(isBar: false, modules: 10))
        #expect(symbol.runs.last == Code39Run(isBar: false, modules: 10))
        #expect(symbol.minimumWidthPoints(displayScale: 2) == 262)
    }

    @Test func normalizesAndSupportsTheStandardCharacterSet() throws {
        let symbol = try Code39Encoder.encode(" ab-12 ")
        #expect(symbol.payload == "AB-12")
        #expect(Code39Encoder.supportedPayloadCharacters.contains("%"))
        #expect(!Code39Encoder.supportedPayloadCharacters.contains("*"))
    }

    @Test func rejectsEmptyAndUnsupportedPayloads() {
        #expect(throws: Code39Error.emptyPayload) {
            try Code39Encoder.encode("  ")
        }
        #expect(throws: Code39Error.unsupportedCharacter("É")) {
            try Code39Encoder.encode("é")
        }
    }
}
