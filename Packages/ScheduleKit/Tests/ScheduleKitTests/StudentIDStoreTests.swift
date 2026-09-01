import Foundation
import Testing
@testable import ScheduleKit

private func makeStudentIDStore() -> (StudentIDStore, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("schedule-kit-student-id-\(UUID().uuidString)",
                                isDirectory: true)
    let fileURL = directory.appendingPathComponent("profile.json")
    return (StudentIDStore(fileURL: fileURL), directory)
}

/// A tiny synthetic JPEG-shaped fixture. The profile validator intentionally
/// checks JPEG markers; no real or user-provided image is needed in tests.
private let syntheticPortraitJPEG = Data([
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00,
    0x01, 0x02, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
    0xFF, 0xD9,
])

@Suite struct StudentIDProfileTests {
    @Test func acceptsLeadingZeroNumberAndRejectsNonNumericOrWrongLength() {
        let profile = StudentIDProfile(studentNumber: "00001234")
        #expect(profile.isValid)
        #expect(StudentIDProfile.normalizedStudentNumber(" 00001234\n") == "00001234")
        #expect(!StudentIDProfile.isValidStudentNumber("123"))
        #expect(!StudentIDProfile.isValidStudentNumber("0000123A"))
        #expect(!StudentIDProfile.isValidStudentNumber("0000123456789"))
    }

    @Test func validatesOptionalDisplayNamePortraitAndMetadata() {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = StudentIDProfile(
            studentNumber: "00001234",
            displayName: "Sample Learner",
            portraitJPEGData: syntheticPortraitJPEG,
            createdAt: timestamp,
            updatedAt: timestamp.addingTimeInterval(30))
        #expect(profile.isValid)
        #expect(profile.portraitJPEGData == syntheticPortraitJPEG)

        #expect(!StudentIDProfile(studentNumber: "00001234",
                                  displayName: "   ").isValid)
        #expect(!StudentIDProfile(studentNumber: "00001234",
                                  portraitJPEGData: Data("not-a-jpeg".utf8)).isValid)
        #expect(!StudentIDProfile(studentNumber: "00001234",
                                  createdAt: timestamp.addingTimeInterval(1),
                                  updatedAt: timestamp).isValid)
    }
}

@Suite struct StudentIDStoreTests {
    @Test func roundTripIsIsolatedAndPreservesLeadingZeros() throws {
        let (store, directory) = makeStudentIDStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let created = Date(timeIntervalSince1970: 1_800_000_000.123)
        let updated = created.addingTimeInterval(45)
        let profile = StudentIDProfile(
            studentNumber: "00001234",
            displayName: "Sample Learner",
            portraitJPEGData: syntheticPortraitJPEG,
            createdAt: created,
            updatedAt: updated)

        #expect(try store.load() == nil)
        #expect(try store.save(profile) == profile)
        #expect(try store.load() == profile)
        #expect(store.exists)

        let persisted = try Data(contentsOf: store.fileURL)
        let json = String(decoding: persisted, as: UTF8.self)
        #expect(json.contains("00001234"))
        #expect(json.contains("portraitJPEGData"))
        #expect(!json.localizedCaseInsensitiveContains("sourceImage"))
        #expect(!json.localizedCaseInsensitiveContains("originalImage"))
    }

    @Test func invalidProfileNeverCreatesAFile() {
        let (store, directory) = makeStudentIDStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let invalid = StudentIDProfile(studentNumber: "student-number")
        #expect(throws: StudentIDStoreError.invalidProfile(.invalidStudentNumber)) {
            try store.save(invalid)
        }
        #expect(!store.exists)
    }

    @Test func malformedPersistedDataIsNotAccepted() throws {
        let (store, directory) = makeStudentIDStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
        try Data("{\"studentNumber\":\"not-valid\"}".utf8)
            .write(to: store.fileURL)

        #expect(throws: StudentIDStoreError.invalidStoredData) {
            try store.load()
        }
    }

    @Test func deleteIsIdempotent() throws {
        let (store, directory) = makeStudentIDStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.save(StudentIDProfile(studentNumber: "00001234"))
        #expect(store.exists)
        try store.delete()
        #expect(!store.exists)
        try store.delete()
        #expect(try store.load() == nil)
    }
}
