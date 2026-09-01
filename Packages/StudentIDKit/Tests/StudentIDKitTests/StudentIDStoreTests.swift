import Foundation
import Testing
@testable import StudentIDKit

@Suite struct StudentIDStoreTests {
    @Test func profileRoundTripsAndCanBeRemoved() {
        let suiteName = "student-id-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = StudentIDStore(defaults: defaults)

        #expect(store.profile == nil)
        let profile = StudentIDProfile(
            studentName: "  Sample   Student ",
            studentNumber: " 00594 "
        )
        store.profile = profile

        #expect(store.profile == StudentIDProfile(
            studentName: "Sample Student",
            studentNumber: "00594"
        ))
        store.profile = nil
        #expect(store.profile == nil)
    }

    @Test func profileValidationProtectsScannerSizing() {
        #expect(StudentIDProfile(studentName: "", studentNumber: "12345").validationMessage != nil)
        #expect(StudentIDProfile(studentName: "Sample Student", studentNumber: "").validationMessage != nil)
        #expect(StudentIDProfile(studentName: "Sample Student", studentNumber: String(repeating: "1", count: 13)).validationMessage != nil)
        #expect(StudentIDProfile(studentName: "Sample Student", studentNumber: "12345").isValid)
    }
}
