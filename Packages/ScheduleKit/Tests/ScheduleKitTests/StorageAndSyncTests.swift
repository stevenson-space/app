import Testing
import Foundation
@testable import ScheduleKit

/// Isolated UserDefaults per test, and a keychain stand-in so no test ever
/// touches the host's real one.
private func makeStore() -> (SharedStore, UserDefaults, String) {
    let (store, defaults, suite, _) = makeStoreWithSecrets()
    return (store, defaults, suite)
}

private func makeStoreWithSecrets() -> (SharedStore, UserDefaults, String, InMemorySecretStore) {
    let suiteName = "sk-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let secrets = InMemorySecretStore()
    return (SharedStore(defaults: defaults, secrets: secrets), defaults, suiteName, secrets)
}

/// Reads as an empty keychain but refuses every write — the shape of a
/// keychain that is reachable but not writable (a missing entitlement, say).
private struct WriteRefusingSecretStore: SecretStore {
    func read(_ key: String) -> SecretReadResult { .missing }
    func write(_ data: Data?, for key: String) throws {
        throw SecretStoreError(status: -34018)
    }
}

@Suite struct SharedStoreTests {
    @Test func configRoundTrip() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var config = UserConfig(lunch: SplitAssignment(basePeriod: 5, choice: .b))
        config.freePeriods = [7]
        config.customizations["3"] = PeriodCustomization(name: "AP Bio", room: "214")
        config.appearance = .dark
        store.userConfig = config
        #expect(store.userConfig == config)
    }

    @Test func overridesRoundTripAndIndexByDay() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let override = DayOverride(
            day: day(2026, 12, 17),
            type: .bell(family: .earlyDismissal, rotation: .rotation2))
        store.overrides = [override]
        #expect(store.overrides == [override])
        #expect(store.overridesByDay[day(2026, 12, 17)] == override)
    }

    @Test func studentIDDataRoundTripsAndClears() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.readStudentIDData() == .missing)
        let payload = Data(#"{"idNumber":"59435"}"#.utf8)
        try store.setStudentIDData(payload)
        #expect(store.readStudentIDData() == .value(payload))
        #expect(store.studentIDData == payload)

        try store.setStudentIDData(nil)
        #expect(store.studentIDData == nil)
        // The identity bytes never live in the preferences plist.
        #expect(defaults.object(forKey: "sk.studentID") == nil)
    }

    @Test func studentIDNeverTouchesUserDefaults() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        try store.setStudentIDData(Data(#"{"idNumber":"59435"}"#.utf8))
        let plist = defaults.dictionaryRepresentation()
        for (key, value) in plist where key.hasPrefix("sk.") {
            #expect((value as? Data).map { String(decoding: $0, as: UTF8.self) }?
                .contains("59435") != true, "\(key) carries the ID number")
        }
    }

    @Test func aLockedKeychainIsNotAnEmptyOne() throws {
        let (store, defaults, suite, secrets) = makeStoreWithSecrets()
        defer { defaults.removePersistentDomain(forName: suite) }

        try store.setStudentIDData(Data(#"{"idNumber":"59435"}"#.utf8))
        secrets.isUnavailable = true
        // Reported as unreadable, not absent, so nothing downstream concludes
        // the student has no ID and cleans up after it.
        #expect(store.readStudentIDData() == .unavailable)
    }

    @Test func migratesAStudentIDLeftInUserDefaults() {
        let (store, defaults, suite, secrets) = makeStoreWithSecrets()
        defer { defaults.removePersistentDomain(forName: suite) }

        let payload = Data(#"{"idNumber":"59435"}"#.utf8)
        defaults.set(payload, forKey: "sk.studentID")
        store.migrateStudentIDToKeychainIfNeeded()

        #expect(secrets.read("sk.studentID") == .value(payload))
        #expect(defaults.object(forKey: "sk.studentID") == nil)
    }

    @Test func servesAndMigratesALegacyCardWhenTheFirstLaunchWasLocked() {
        let (store, defaults, suite, secrets) = makeStoreWithSecrets()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Upgraded install launched into the background before first unlock:
        // the migration deferred, so the card is still only in the plist.
        let payload = Data(#"{"idNumber":"59435"}"#.utf8)
        defaults.set(payload, forKey: "sk.studentID")
        secrets.isUnavailable = true
        store.migrateStudentIDToKeychainIfNeeded()
        #expect(store.readStudentIDData() == .unavailable)

        // The device unlocks. Nothing runs the migration again for the life of
        // the process, so the read has to pick it up or the ID stays invisible.
        secrets.isUnavailable = false
        #expect(store.readStudentIDData() == .value(payload))
        #expect(secrets.read("sk.studentID") == .value(payload))
        #expect(defaults.object(forKey: "sk.studentID") == nil)
    }

    @Test func stillServesTheLegacyCardWhenTheKeychainWriteKeepsFailing() {
        let suiteName = "sk-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedStore(defaults: defaults, secrets: WriteRefusingSecretStore())

        let payload = Data(#"{"idNumber":"59435"}"#.utf8)
        defaults.set(payload, forKey: "sk.studentID")

        // A keychain that reads empty but refuses every write. Reporting the
        // card missing here would orphan-delete the student's photo while the
        // card itself is sitting right there in the plist.
        #expect(store.readStudentIDData() == .value(payload))
        #expect(defaults.data(forKey: "sk.studentID") == payload)
    }

    @Test func keepsTheLegacyBlobWhenTheKeychainWriteFails() {
        let (store, defaults, suite, secrets) = makeStoreWithSecrets()
        defer { defaults.removePersistentDomain(forName: suite) }

        let payload = Data(#"{"idNumber":"59435"}"#.utf8)
        defaults.set(payload, forKey: "sk.studentID")
        // A background launch while the device is still locked.
        secrets.isUnavailable = true
        store.migrateStudentIDToKeychainIfNeeded()
        #expect(defaults.data(forKey: "sk.studentID") == payload)

        secrets.isUnavailable = false
        store.migrateStudentIDToKeychainIfNeeded()
        #expect(secrets.read("sk.studentID") == .value(payload))
        #expect(defaults.object(forKey: "sk.studentID") == nil)
    }

    @Test func studentIDIsCarriedByTheAppGroupMigration() {
        // Anything not in this list is silently left behind in the old suite.
        #expect(SharedStore.migratableKeys.contains("sk.studentID"))
    }

    @Test func mapURLDefaultsAndReset() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.mapURL == SharedStore.defaultMapURL)
        #expect(store.isUsingDefaultMapURL)

        // Still honoured when it names an approved source, so an install that
        // persisted one before the editor was removed keeps working.
        let sameHost = "https://raw.githubusercontent.com/stevenson-space/shs/dev/dates.json"
        defaults.set(sameHost, forKey: "sk.mapURL")
        #expect(store.mapURL.absoluteString == sameHost)
        #expect(!store.isUsingDefaultMapURL)

        store.resetMapURL()
        #expect(store.mapURL == SharedStore.defaultMapURL)
    }

    @Test func mapURLFallsBackToTheDefaultForAnySourceNotOnTheAllowList() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        for raw in ["http://raw.githubusercontent.com/a/b.json",       // not HTTPS
                    "https://evil.example.com/dates.json",             // wrong host
                    "https://raw.githubusercontent.com:8443/a.json",   // odd port
                    "https://user:pw@raw.githubusercontent.com/a.json", // credentials
                    "file:///etc/passwd",
                    "not a url at all"] {
            defaults.set(raw, forKey: "sk.mapURL")
            #expect(store.mapURL == SharedStore.defaultMapURL, "accepted \(raw)")
        }
    }

    @Test func retiringACustomMapURLClearsIt() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("https://raw.githubusercontent.com/x/y.json", forKey: "sk.mapURL")
        store.retireCustomMapURLIfNeeded()
        #expect(defaults.object(forKey: "sk.mapURL") == nil)
    }

    @Test func tolerantDecodingOfOlderBlobs() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        // A blob from a hypothetical older version, missing newer fields.
        defaults.set(Data(#"{"lunch":{"basePeriod":4,"choice":"A"}}"#.utf8), forKey: "sk.userConfig")
        let config = store.userConfig
        #expect(config.lunch == SplitAssignment(basePeriod: 4, choice: .a))
        #expect(config.freePeriods.isEmpty)
        #expect(config.timeFormat == .system)
        #expect(config.appearance == .system)

        defaults.set(Data(#"{"blockEndEnabled":true}"#.utf8), forKey: "sk.notificationPrefs")
        let prefs = store.notificationPrefs
        #expect(prefs.blockEndEnabled)
        #expect(prefs.blockEndLeadMinutes == 5)
    }

    @Test func defaultsWhenEmpty() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.userConfig == UserConfig())
        #expect(store.overrides.isEmpty)
        #expect(store.cachedMapData == nil)
        #expect(store.fetchMetadata == FetchMetadata())
        #expect(store.cachedLunchMenuData == nil)
        #expect(store.lunchFetchMetadata == FetchMetadata())
        #expect(!store.notificationPrefs.anyEnabled)
    }
}

// MARK: - Sync

/// URLProtocol stub: each test installs a handler returning (status, headers, body).
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, [String: String], Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, headers, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct SyncServiceTests {
    let validJSON = Data(#"{"Late Arrival": ["9/18/2026"]}"#.utf8)
    let updatedJSON = Data(#"{"Late Arrival": ["9/18/2026", "10/16/2026"]}"#.utf8)

    func makeService(_ store: SharedStore) -> ScheduleSyncService {
        let session = ScheduleSyncService.makeSession(protocolClasses: [StubURLProtocol.self])
        return ScheduleSyncService(store: store, session: session)
    }

    @Test func successfulFetchCommitsDataEtagAndTimestamps() async {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let json = validJSON
        StubURLProtocol.handler = { _ in (200, ["ETag": "\"abc\""], json) }

        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let result = await makeService(store).refresh(force: true, now: t0)

        #expect(result == .updated)
        #expect(store.cachedMapData == validJSON)
        let meta = store.fetchMetadata
        #expect(meta.etag == "\"abc\"")
        #expect(meta.lastSuccess == t0)
        #expect(meta.lastChanged == t0)
        #expect(meta.lastError == nil)
    }

    @Test func notModified304KeepsContentButRecordsSuccess() async {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.cachedMapData = validJSON
        store.fetchMetadata = FetchMetadata(etag: "\"abc\"")
        StubURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
            return (304, [:], Data())
        }

        let t1 = Date(timeIntervalSince1970: 1_800_100_000)
        let result = await makeService(store).refresh(force: true, now: t1)

        #expect(result == .notModified)
        #expect(store.cachedMapData == validJSON)
        #expect(store.fetchMetadata.lastSuccess == t1)
        #expect(store.fetchMetadata.lastChanged == nil)
    }

    @Test func garbagePayloadNeverTouchesLastGoodCache() async {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.cachedMapData = validJSON
        StubURLProtocol.handler = { _ in (200, [:], Data("<html>oops</html>".utf8)) }

        let result = await makeService(store).refresh(force: true)

        guard case .failed = result else {
            Issue.record("expected failure, got \(result)"); return
        }
        #expect(store.cachedMapData == validJSON)
        #expect(store.fetchMetadata.lastError != nil)
        #expect(store.fetchMetadata.lastSuccess == nil)
    }

    @Test func httpErrorRecordsFailureAndKeepsCache() async {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.cachedMapData = validJSON
        StubURLProtocol.handler = { _ in (500, [:], Data()) }

        let result = await makeService(store).refresh(force: true)
        #expect(result == .failed("HTTP 500"))
        #expect(store.cachedMapData == validJSON)
        #expect(store.fetchMetadata.lastError == "HTTP 500")
    }

    @Test func transportErrorRecordsFailureAndKeepsCache() async {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.cachedMapData = validJSON
        let transportError = URLError(.notConnectedToInternet)
        StubURLProtocol.handler = { _ in throw transportError }

        let result = await makeService(store).refresh(force: true)
        #expect(result == .failed(transportError.localizedDescription))
        #expect(store.cachedMapData == validJSON)
        #expect(store.fetchMetadata.lastError != nil)
        #expect(store.fetchMetadata.lastSuccess == nil)
    }

    @Test func byteIdenticalContentIsNotModified() async {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.cachedMapData = validJSON
        let json = validJSON
        StubURLProtocol.handler = { _ in (200, [:], json) }

        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let result = await makeService(store).refresh(force: true, now: t0)
        #expect(result == .notModified)
        #expect(store.fetchMetadata.lastChanged == nil)
    }

    @Test func changedContentUpdatesCache() async {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.cachedMapData = validJSON
        let json = updatedJSON
        StubURLProtocol.handler = { _ in (200, [:], json) }

        let result = await makeService(store).refresh(force: true)
        #expect(result == .updated)
        #expect(store.cachedMapData == updatedJSON)
    }

    @Test func throttleSkipsRecentAttemptsUnlessForced() async {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let json = validJSON
        StubURLProtocol.handler = { _ in (200, [:], json) }
        let service = makeService(store)

        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = await service.refresh(force: true, now: t0)

        let soon = t0.addingTimeInterval(600)
        #expect(await service.refresh(force: false, now: soon) == .skippedThrottled)
        // A forced refresh runs anyway — and restarts the throttle window.
        #expect(await service.refresh(force: true, now: soon) == .notModified)

        let later = soon.addingTimeInterval(ScheduleSyncService.throttleInterval + 1)
        #expect(await service.refresh(force: false, now: later) == .notModified)
    }
}
