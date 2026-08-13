import Testing
import Foundation
@testable import ScheduleKit

/// Isolated UserDefaults per test.
private func makeStore() -> (SharedStore, UserDefaults, String) {
    let suiteName = "sk-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (SharedStore(defaults: defaults), defaults, suiteName)
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

    @Test func mapURLDefaultsAndReset() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.mapURL == SharedStore.defaultMapURL)
        #expect(store.isUsingDefaultMapURL)

        let custom = URL(string: "https://example.com/dates.json")!
        store.mapURL = custom
        #expect(store.mapURL == custom)
        #expect(!store.isUsingDefaultMapURL)

        store.resetMapURL()
        #expect(store.mapURL == SharedStore.defaultMapURL)
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
        #expect(!store.notificationPrefs.anyEnabled)
        #expect(!store.lunchPromptDismissed)
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
