import Testing
import Foundation
@testable import ScheduleKit

@Suite struct SmokeTests {
    @Test func schoolTimeZoneIsChicago() {
        #expect(SchoolTime.timeZone.identifier == "America/Chicago")
    }

    @Test func bundledScheduleResourceExists() throws {
        let data = try BundledResources.bellSchedulesData()
        #expect(!data.isEmpty)
        _ = try JSONSerialization.jsonObject(with: data)
    }

    @Test func fixtureSnapshotExists() throws {
        let url = try #require(Bundle.module.url(
            forResource: "schedule-dates-snapshot", withExtension: "json", subdirectory: "Fixtures"))
        _ = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }
}
