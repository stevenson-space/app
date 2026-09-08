import Testing
import Foundation
@testable import ScheduleKit

@Suite struct LunchMenuParserTests {
    @Test func bundledManifestMatchesWebsiteRotation() throws {
        let menu = try LunchMenuParser.loadBundled()

        let openingTuesday = try #require(menu.menu(for: day(2026, 8, 11)))
        #expect(items(.comfort, in: openingTuesday) == ["Chicken Shawarma with Pita"])
        #expect(items(.sides, in: openingTuesday)
                == ["Simple Green Salad", "Lemon Rice with Tzatziki Sauce"])
        #expect(items(.soup, in: openingTuesday) == ["Smokey Poblano", "Chicken Noodle"])
        #expect(items(.special, in: openingTuesday) == ["Tacos Tuesday"])

        // The website advances the four-week rotation every seven elapsed
        // calendar days from validFrom (Tuesday in this manifest).
        let nextTuesday = try #require(menu.menu(for: day(2026, 8, 18)))
        #expect(items(.comfort, in: nextTuesday) == ["Moroccan Chickpea Stew with Naan"])
        #expect(items(.international, in: nextTuesday) == ["Pasta Bowl"])
    }

    @Test func weekendAndOutOfRangeDatesHaveNoMenu() throws {
        let menu = try LunchMenuParser.loadBundled()
        #expect(menu.menu(for: day(2026, 8, 9)) == nil)
        #expect(menu.menu(for: day(2026, 8, 15)) == nil)
        #expect(menu.menu(for: day(2027, 6, 1)) == nil)
    }

    @Test func semesterSwitchChangesSpecialRotation() throws {
        let menu = try LunchMenuParser.loadBundled()
        let firstSemesterThursday = try #require(menu.menu(for: day(2026, 12, 31)))
        let secondSemesterThursday = try #require(menu.menu(for: day(2027, 1, 7)))
        #expect(items(.special, in: firstSemesterThursday) == ["Nachos Thursday"])
        #expect(items(.special, in: secondSemesterThursday) == ["Chilli Thursday"])
    }

    @Test func malformedManifestsFailWholesale() throws {
        #expect(throws: LunchMenuParserError.self) {
            _ = try LunchMenuParser.parse(Data("not json".utf8))
        }
        #expect(throws: LunchMenuParserError.self) {
            _ = try LunchMenuParser.parse(validManifest(offset: 4))
        }
        #expect(throws: LunchMenuParserError.self) {
            _ = try LunchMenuParser.parse(validManifest(specialWeekdays: 4))
        }
        #expect(throws: LunchMenuParserError.self) {
            _ = try LunchMenuParser.parse(
                Data(repeating: 0x20, count: LunchMenuParser.maxBytes + 1))
        }
    }

    @Test func rotationLengthComesFromTheStationsNotAFixedFour() throws {
        // The website moved from a four-week to a five-week rotation; a parser
        // that insists on four rejects every live manifest.
        let menu = try LunchMenuParser.parse(validManifest(weeks: 5))
        #expect(menu.rotationWeeks == 5)

        let firstTuesday = try #require(menu.menu(for: day(2026, 8, 11)))
        #expect(items(.international, in: firstTuesday) == ["week-0"])
        let fifthTuesday = try #require(menu.menu(for: day(2026, 9, 8)))
        #expect(items(.international, in: fifthTuesday) == ["week-4"])
        // Week six wraps to the top of the rotation, not to week two.
        let sixthTuesday = try #require(menu.menu(for: day(2026, 9, 15)))
        #expect(items(.international, in: sixthTuesday) == ["week-0"])
    }

    @Test func stationsMustAgreeOnTheRotationLength() {
        #expect(throws: LunchMenuParserError.self) {
            _ = try LunchMenuParser.parse(validManifest(weeks: 5, soupWeeks: 4))
        }
        // Offset is bounded by the published rotation, not by a constant.
        #expect(throws: LunchMenuParserError.self) {
            _ = try LunchMenuParser.parse(validManifest(weeks: 5, offset: 5))
        }
        #expect(throws: Never.self) {
            _ = try LunchMenuParser.parse(validManifest(weeks: 5, offset: 4))
        }
    }

    private func items(_ station: LunchMenuStation, in menu: LunchMenuDay) -> [String]? {
        menu.sections.first { $0.station == station }?.items
    }
}

@Suite(.serialized) struct LunchMenuSyncTests {
    @Test func refreshBuildsTheManifestFromTheSixRotatingStationFiles() async throws {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        LunchStubURLProtocol.handler = { request in stationResponse(for: request) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        #expect(await service.refresh(force: true, now: now) == .updated)

        let expected = Set(SharedStore.lunchStationNames.map { SharedStore.lunchStationURL(named: $0) })
        #expect(Set(LunchStubURLProtocol.requestedURLs) == expected)
        // The consolidated manifest is gone from the website; nothing may ask
        // for it, not even as a probe.
        #expect(!LunchStubURLProtocol.requestedURLs.contains { $0.lastPathComponent == "lunch-menu.json" })

        let cached = try #require(store.cachedLunchMenuData)
        let menu = try LunchMenuParser.parse(cached)
        // The bundled manifest keeps supplying the rotation metadata the
        // website does not publish per station.
        let bundled = try LunchMenuParser.loadBundled()
        #expect(menu.validFrom == bundled.validFrom)
        #expect(menu.validTo == bundled.validTo)
        #expect(menu.semesterSwitch == bundled.semesterSwitch)
        #expect(menu.offset == bundled.offset)
        // Station data is the live payload, and its five-week rotation wins
        // over the bundled four.
        #expect(menu.rotationWeeks == 5)
        let tuesday = try #require(menu.menu(for: day(2026, 8, 11)))
        #expect(tuesday.sections.first { $0.station == .comfort }?.items == ["a-comfort-w0-d1"])
        #expect(tuesday.sections.first { $0.station == .soup }?.items == ["a-soup-w0-a", "a-soup-w0-b"])

        #expect(store.lunchFetchMetadata.lastSuccess == now)
        #expect(store.lunchFetchMetadata.lastChanged == now)
        #expect(store.lunchFetchMetadata.lastError == nil)
        #expect(store.lunchFetchMetadata.etag == nil)
    }

    @Test func changedLiveDataReplacesTheCachedManifest() async throws {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let seed = SeedBox()
        LunchStubURLProtocol.reset()
        LunchStubURLProtocol.handler = { request in stationResponse(for: request, seed: seed.value) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        let first = Date(timeIntervalSince1970: 1_900_000_000)

        #expect(await service.refresh(force: true, now: first) == .updated)
        let firstCache = try #require(store.cachedLunchMenuData)

        // Same menu published again: reached, validated, nothing rewritten.
        #expect(await service.refresh(force: true, now: first + 10) == .notModified)
        #expect(store.cachedLunchMenuData == firstCache)
        #expect(store.lunchFetchMetadata.lastChanged == first)
        #expect(store.lunchFetchMetadata.lastSuccess == first + 10)

        // The kitchen publishes a new rotation.
        seed.value = "b"
        #expect(await service.refresh(force: true, now: first + 20) == .updated)
        let secondCache = try #require(store.cachedLunchMenuData)
        #expect(secondCache != firstCache)
        #expect(store.lunchFetchMetadata.lastChanged == first + 20)
        let menu = try LunchMenuParser.parse(secondCache)
        let tuesday = try #require(menu.menu(for: day(2026, 8, 11)))
        #expect(tuesday.sections.first { $0.station == .comfort }?.items == ["b-comfort-w0-d1"])
    }

    @Test func oneFailedStationKeepsTheLastGoodMenu() async throws {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        LunchStubURLProtocol.handler = { request in stationResponse(for: request) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        let first = Date(timeIntervalSince1970: 1_900_000_000)
        #expect(await service.refresh(force: true, now: first) == .updated)
        let lastGood = try #require(store.cachedLunchMenuData)

        // Five stations still serve; the sixth does not. A partial menu is
        // worse than yesterday's complete one, so nothing is committed.
        LunchStubURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "soup.json" { return (500, [:], Data()) }
            return stationResponse(for: request, seed: "b")
        }
        guard case .failed = await service.refresh(force: true, now: first + 20) else {
            Issue.record("Expected a failing station to fail the refresh")
            return
        }
        #expect(store.cachedLunchMenuData == lastGood)
        #expect(store.lunchFetchMetadata.lastError != nil)
        #expect(store.lunchFetchMetadata.lastChanged == first)
        #expect(store.lunchFetchMetadata.lastSuccess == first)
    }

    @Test func stationsThatDisagreeOnTheRotationKeepTheLastGoodMenu() async throws {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        LunchStubURLProtocol.handler = { request in stationResponse(for: request) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        #expect(await service.refresh(force: true) == .updated)
        let lastGood = try #require(store.cachedLunchMenuData)

        LunchStubURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "soup.json" {
                return stationResponse(for: request, weeks: 4)
            }
            return stationResponse(for: request)
        }
        guard case .failed = await service.refresh(force: true) else {
            Issue.record("Expected an inconsistent rotation to fail validation")
            return
        }
        #expect(store.cachedLunchMenuData == lastGood)
    }

    @Test func throttleSkipsRecentAttemptsUnlessForced() async {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        LunchStubURLProtocol.handler = { request in stationResponse(for: request) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        #expect(await service.refresh(force: true, now: now) == .updated)
        LunchStubURLProtocol.reset()

        // A foreground activation minutes later must not re-fetch six files.
        #expect(await service.refresh(force: false, now: now + 60) == .skippedThrottled)
        #expect(LunchStubURLProtocol.requestedURLs.isEmpty)

        // Pull-to-refresh bypasses the window.
        #expect(await service.refresh(force: true, now: now + 60) == .notModified)
        #expect(LunchStubURLProtocol.requestedURLs.count == SharedStore.lunchStationNames.count)

        // So does an activation past the window, measured from that forced
        // attempt rather than from the first one.
        LunchStubURLProtocol.reset()
        let pastWindow = now + 60 + LunchMenuSyncService.throttleInterval + 1
        #expect(await service.refresh(force: false, now: pastWindow) == .notModified)
        #expect(LunchStubURLProtocol.requestedURLs.count == SharedStore.lunchStationNames.count)
    }

    @Test func anOversizedStationFileIsRejected() async {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        LunchStubURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "soup.json" {
                // Six of these are fetched at once, so an endpoint serving an
                // endless body must be cut off mid-stream, not buffered whole.
                return (200, [:], Data(repeating: 0x20, count: LunchMenuParser.maxBytes * 4))
            }
            return stationResponse(for: request)
        }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())

        guard case .failed = await service.refresh(force: true) else {
            Issue.record("Expected an oversized station to fail")
            return
        }
        #expect(store.cachedLunchMenuData == nil)
    }
}

/// Lets a stub handler serve a different menu on a later refresh.
private final class SeedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = "a"
    var value: String {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}

private final class LunchStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (Int, [String: String], Data))?
    /// The six stations are fetched concurrently, so recording is locked.
    private nonisolated(unsafe) static var recorded: [URL] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        recorded = []
        lock.unlock()
    }

    static var requestedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let url = request.url {
            Self.lock.lock()
            Self.recorded.append(url)
            Self.lock.unlock()
        }
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

private func makeLunchStore() -> (SharedStore, UserDefaults, String) {
    let suite = "sk-lunch-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return (SharedStore(defaults: defaults, secrets: InMemorySecretStore()), defaults, suite)
}

private func makeStubSession() -> URLSession {
    ScheduleSyncService.makeSession(protocolClasses: [LunchStubURLProtocol.self])
}

private func validManifest(weeks: Int = 4, soupWeeks: Int? = nil,
                           offset: Int = 0, specialWeekdays: Int = 5) -> Data {
    let weeklyStrings = (0..<weeks).map { "week-\($0)" }
    let weeklyPairs = (0..<(soupWeeks ?? weeks)).map { ["week-\($0)-a", "week-\($0)-b"] }
    let special = Array(repeating: "special", count: specialWeekdays)
    let object: [String: Any] = [
        "validFrom": "2026-08-11",
        "validTo": "2027-05-31",
        "semesterSwitch": "2027-01-01",
        "offset": offset,
        "stations": [
            "comfort": ["cadence": "weekly", "data": weeklyStrings],
            "mindful": ["cadence": "weekly", "data": weeklyStrings],
            "sides": ["cadence": "weekly",
                      "data": (0..<weeks).map { ["week-\($0)-a", "week-\($0)-b"] }],
            "soup": ["cadence": "weekly", "data": weeklyPairs],
            "international": ["cadence": "weekly", "data": weeklyStrings],
        ],
        "special": [special, special],
    ]
    return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

/// Mirrors the live files: `comfort`, `mindful` and `sides` are daily, the
/// rest weekly, and every station runs the same five-week rotation.
private func stationPayload(_ name: String, weeks: Int, seed: String) -> Data {
    func daily<T>(_ make: (Int, Int) -> T) -> [[T]] {
        (0..<weeks).map { week in (0..<5).map { make(week, $0) } }
    }
    let value: Any
    switch name {
    case "comfort", "mindful":
        value = ["cadence": "daily", "data": daily { "\(seed)-\(name)-w\($0)-d\($1)" }]
    case "sides":
        value = ["cadence": "daily",
                 "data": daily { ["\(seed)-sides-w\($0)-d\($1)-a", "\(seed)-sides-w\($0)-d\($1)-b"] }]
    case "international":
        value = ["cadence": "weekly", "data": (0..<weeks).map { "\(seed)-international-w\($0)" }]
    case "soup":
        value = ["cadence": "weekly",
                 "data": (0..<weeks).map { ["\(seed)-soup-w\($0)-a", "\(seed)-soup-w\($0)-b"] }]
    case "special":
        value = [Array(repeating: "\(seed)-special-one", count: 5),
                 Array(repeating: "\(seed)-special-two", count: 5)]
    default:
        value = [:]
    }
    return try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}

private func stationResponse(for request: URLRequest, weeks: Int = 5,
                             seed: String = "a") -> (Int, [String: String], Data) {
    guard let name = request.url?.deletingPathExtension().lastPathComponent,
          SharedStore.lunchStationNames.contains(name) else {
        return (404, [:], Data())
    }
    return (200, [:], stationPayload(name, weeks: weeks, seed: seed))
}
