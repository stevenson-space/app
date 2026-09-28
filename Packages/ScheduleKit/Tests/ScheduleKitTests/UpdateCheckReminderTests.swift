import Foundation
import Testing
@testable import ScheduleKit

private func instant(_ year: Int, _ month: Int, _ date: Int, _ hour: Int, _ minute: Int) -> Date {
    TestSupport.at(day(year, month, date), hour, minute)
}

@Suite struct UpdateCheckReminderTests {
    @Test func recentCheckKeepsOldContentQuiet() {
        let now = instant(2026, 9, 28, 12, 0)
        let metadata = FetchMetadata(
            lastSuccess: instant(2026, 9, 27, 12, 0),
            lastChanged: instant(2026, 1, 1, 12, 0))
        #expect(!metadata.isUpdateCheckOverdue(at: now))
    }

    @Test func reminderStartsAfterFiveCalendarDaysIncludingDST() {
        let metadata = FetchMetadata(lastSuccess: instant(2026, 3, 4, 12, 0))
        // Chicago changes to daylight saving time on March 8.
        #expect(!metadata.isUpdateCheckOverdue(at: instant(2026, 3, 9, 11, 59)))
        #expect(metadata.isUpdateCheckOverdue(at: instant(2026, 3, 9, 12, 0)))
    }

    @Test func failedAttemptDoesNotMakeAnOldCheckRecent() {
        let now = instant(2026, 9, 28, 12, 0)
        let metadata = FetchMetadata(
            lastAttempt: now,
            lastSuccess: instant(2026, 9, 20, 12, 0),
            lastError: "Offline")
        #expect(metadata.isUpdateCheckOverdue(at: now))
    }

    @Test func newInstallGetsAGracePeriodEvenWhenRetriesFail() {
        #expect(!FetchMetadata().isUpdateCheckOverdue(at: instant(2026, 9, 28, 12, 0)))
        let metadata = FetchMetadata(
            firstAttempt: instant(2026, 9, 23, 12, 0),
            lastAttempt: instant(2026, 9, 28, 12, 0),
            lastError: "Offline")
        #expect(!metadata.isUpdateCheckOverdue(at: instant(2026, 9, 27, 12, 0)))
        #expect(metadata.isUpdateCheckOverdue(at: instant(2026, 9, 28, 12, 0)))
    }

    @Test func successfulCheckResetsTheGracePeriod() {
        let metadata = FetchMetadata(
            firstAttempt: instant(2026, 9, 1, 12, 0),
            lastSuccess: instant(2026, 9, 28, 12, 0))
        #expect(!metadata.isUpdateCheckOverdue(at: instant(2026, 9, 28, 12, 0)))
        #expect(!metadata.isUpdateCheckOverdue(at: instant(2026, 10, 3, 11, 59)))
        #expect(metadata.isUpdateCheckOverdue(at: instant(2026, 10, 3, 12, 0)))
    }

    @Test func legacyMetadataUsesItsKnownAttemptUntilTheNextCheck() throws {
        let legacy = FetchMetadata(lastAttempt: instant(2026, 9, 23, 12, 0))
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(FetchMetadata.self, from: data)
        #expect(decoded.firstAttempt == nil)
        #expect(decoded.isUpdateCheckOverdue(at: instant(2026, 9, 28, 12, 0)))
        #expect(try JSONDecoder().decode(FetchMetadata.self, from: Data("{}".utf8)) == FetchMetadata())
    }

    @Test func clockEarlierThanTheLastCheckDoesNotWarn() {
        let metadata = FetchMetadata(lastSuccess: instant(2026, 9, 28, 12, 0))
        #expect(!metadata.isUpdateCheckOverdue(at: instant(2026, 9, 27, 12, 0)))
    }
}
