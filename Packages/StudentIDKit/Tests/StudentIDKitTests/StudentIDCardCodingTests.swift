import Foundation
import Testing
@testable import StudentIDKit

@Suite struct StudentIDCardCodingTests {

    private func card(number: String = "59435") -> StudentIDCard {
        StudentIDCard(idNumber: number, barcodePayload: number, requiresCheckDigit: false,
                      fullName: "Riley Vasquez", gradeLevel: 12, schoolYearStart: 2026,
                      importedAt: Date(timeIntervalSince1970: 1_780_000_000))
    }

    @Test func roundTripsThroughStorage() throws {
        let original = card()
        let restored = try #require(StudentIDCard.decoded(from: original.encoded()))
        #expect(restored == original)
    }

    @Test func toleratesAPayloadWrittenByAnOlderVersion() throws {
        let data = Data(#"{"idNumber":"59435"}"#.utf8)
        let restored = try #require(StudentIDCard.decoded(from: data))
        #expect(restored.idNumber == "59435")
        #expect(restored.barcodePayload == "59435")
        #expect(restored.fullName == nil)
        #expect(restored.requiresCheckDigit == false)
    }

    @Test func refusesAStoredNumberThatIsNotAStudentNumber() {
        // Editing the stored file is the other way someone could try to put a
        // number the school never issued on screen.
        for payload in [#"{"idNumber":"NOT-A-NUMBER"}"#,
                        #"{"idNumber":"1"}"#,
                        #"{"idNumber":"1234567890123"}"#,
                        #"{"idNumber":"59435","barcodePayload":"HACKED"}"#] {
            #expect(StudentIDCard.decoded(from: Data(payload.utf8)) == nil,
                    "accepted \(payload)")
        }
    }

    @Test func dropsImplausibleGradesAndYears() throws {
        let data = Data(#"{"idNumber":"59435","gradeLevel":99,"schoolYearStart":1200}"#.utf8)
        let restored = try #require(StudentIDCard.decoded(from: data))
        #expect(restored.gradeLevel == nil)
        #expect(restored.schoolYearStart == nil)
    }

    @Test func formatsTheSchoolYearTheWayTheCardPrintsIt() {
        #expect(card().schoolYearLabel == "26\u{2013}27")
        #expect(card().gradeLabel == "Grade 12")
    }
}

@Suite struct StudentIDPhotoStoreTests {

    private func temporaryStore() -> (StudentIDPhotoStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("student-id-tests-\(UUID().uuidString)", isDirectory: true)
        return (StudentIDPhotoStore(directory: directory), directory)
    }

    @Test func savesLoadsAndRemovesThePhoto() throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(store.loadData() == nil)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        try store.save(jpeg)
        #expect(store.loadData() == jpeg)

        store.remove()
        #expect(store.loadData() == nil)
    }

    @Test func overwritesAnEarlierPhotoOnReimport() throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.save(Data([0x01, 0x02]))
        try store.save(Data([0x03, 0x04, 0x05]))
        #expect(store.loadData() == Data([0x03, 0x04, 0x05]))
    }
}
