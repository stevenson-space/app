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

    private func items(_ station: LunchMenuStation, in menu: LunchMenuDay) -> [String]? {
        menu.sections.first { $0.station == station }?.items
    }
}

@Suite(.serialized) struct LunchMenuSyncTests {
    @Test func successfulFetchCommitsValidatedManifestAndMetadata() async {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = validManifest()
        LunchStubURLProtocol.handler = { request in
            #expect(request.url == SharedStore.defaultLunchMenuURL)
            return (200, ["ETag": "\"lunch-1\""], data)
        }
        let session = ScheduleSyncService.makeSession(protocolClasses: [LunchStubURLProtocol.self])
        let service = LunchMenuSyncService(store: store, session: session)
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        #expect(await service.refresh(force: true, now: now) == .updated)
        #expect(store.cachedLunchMenuData == data)
        #expect(store.lunchFetchMetadata.etag == "\"lunch-1\"")
        #expect(store.lunchFetchMetadata.lastSuccess == now)
    }

    @Test func automaticRefreshWaitsAnHourButManualRefreshBypassesThrottle() async {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = validManifest()
        LunchStubURLProtocol.handler = { _ in (200, [:], data) }
        let session = ScheduleSyncService.makeSession(protocolClasses: [LunchStubURLProtocol.self])
        let service = LunchMenuSyncService(store: store, session: session)
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        #expect(await service.refresh(force: false, now: now) == .updated)
        LunchStubURLProtocol.handler = { _ in
            Issue.record("A throttled refresh must not send a request")
            return (500, [:], Data())
        }
        #expect(await service.refresh(force: false, now: now.addingTimeInterval(3599))
                == .skippedThrottled)
        #expect(store.lunchFetchMetadata.lastAttempt == now)

        LunchStubURLProtocol.handler = { _ in (200, [:], data) }
        let manualCheck = now.addingTimeInterval(3599)
        #expect(await service.refresh(force: true, now: manualCheck) == .notModified)
        #expect(store.lunchFetchMetadata.lastSuccess == manualCheck)
        #expect(store.lunchFetchMetadata.lastChanged == now)

        let nextAutomaticCheck = manualCheck.addingTimeInterval(3600)
        #expect(await service.refresh(force: false, now: nextAutomaticCheck) == .notModified)
        #expect(store.lunchFetchMetadata.lastSuccess == nextAutomaticCheck)
    }

    @Test func unchangedRefreshRecordsSuccessfulCheckAndClearsPreviousError() async {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = validManifest()
        LunchStubURLProtocol.handler = { _ in (200, ["ETag": "\"lunch-1\""], data) }
        let session = ScheduleSyncService.makeSession(protocolClasses: [LunchStubURLProtocol.self])
        let service = LunchMenuSyncService(store: store, session: session)
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        #expect(await service.refresh(force: true, now: now) == .updated)

        LunchStubURLProtocol.handler = { _ in (503, [:], Data()) }
        #expect(await service.refresh(force: true, now: now.addingTimeInterval(1))
                == .failed("HTTP 503"))
        #expect(store.lunchFetchMetadata.lastError != nil)
        #expect(store.lunchFetchMetadata.lastSuccess == now)
        #expect(store.cachedLunchMenuData == data)

        LunchStubURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"lunch-1\"")
            return (304, [:], Data())
        }
        let checked = now.addingTimeInterval(2)
        #expect(await service.refresh(force: true, now: checked) == .notModified)
        #expect(store.lunchFetchMetadata.lastSuccess == checked)
        #expect(store.lunchFetchMetadata.lastChanged == now)
        #expect(store.lunchFetchMetadata.lastError == nil)
        #expect(store.cachedLunchMenuData == data)
    }

    @Test func invalidFetchKeepsLastGoodMenu() async {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let lastGood = validManifest()
        store.cachedLunchMenuData = lastGood
        LunchStubURLProtocol.handler = { _ in (200, [:], Data(#"{"offset":99}"#.utf8)) }
        let session = ScheduleSyncService.makeSession(protocolClasses: [LunchStubURLProtocol.self])
        let service = LunchMenuSyncService(store: store, session: session)

        guard case .failed = await service.refresh(force: true) else {
            Issue.record("Expected invalid payload to fail")
            return
        }
        #expect(store.cachedLunchMenuData == lastGood)
        #expect(store.lunchFetchMetadata.lastError != nil)
    }

    @Test func missingManifestFallsBackToExistingRawStationFiles() async throws {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.handler = { request in
            guard let filename = request.url?.lastPathComponent else {
                return (400, [:], Data())
            }
            if filename == "lunch-menu.json" { return (404, [:], Data()) }
            return (200, [:], legacyPayload(filename: filename))
        }
        let session = ScheduleSyncService.makeSession(protocolClasses: [LunchStubURLProtocol.self])
        let service = LunchMenuSyncService(store: store, session: session)

        #expect(await service.refresh(force: true) == .updated)
        let cached = try #require(store.cachedLunchMenuData)
        let menu = try LunchMenuParser.parse(cached)
        let dayMenu = try #require(menu.menu(for: day(2026, 8, 11)))
        #expect(dayMenu.sections.first { $0.station == .comfort }?.items == ["comfort-one"])
        #expect(store.lunchFetchMetadata.etag == nil)
    }
}

private final class LunchStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (Int, [String: String], Data))?

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

private func makeLunchStore() -> (SharedStore, UserDefaults, String) {
    let suite = "sk-lunch-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return (SharedStore(defaults: defaults), defaults, suite)
}

private func validManifest(offset: Int = 0, specialWeekdays: Int = 5) -> Data {
    let weeklyStrings = ["one", "two", "three", "four"]
    let weeklyPairs = [["one-a", "one-b"], ["two-a", "two-b"],
                       ["three-a", "three-b"], ["four-a", "four-b"]]
    let special = Array(repeating: "special", count: specialWeekdays)
    let object: [String: Any] = [
        "validFrom": "2026-08-11",
        "validTo": "2027-05-31",
        "semesterSwitch": "2027-01-01",
        "offset": offset,
        "stations": [
            "comfort": ["cadence": "weekly", "data": weeklyStrings],
            "mindful": ["cadence": "weekly", "data": weeklyStrings],
            "sides": ["cadence": "weekly", "data": weeklyPairs],
            "soup": ["cadence": "weekly", "data": weeklyPairs],
            "international": ["cadence": "weekly", "data": weeklyStrings],
        ],
        "special": [special, special],
    ]
    return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func legacyPayload(filename: String) -> Data {
    let strings = filename.replacingOccurrences(of: ".json", with: "")
    let weeklyStrings = (1...4).map { "\(strings)-\(["one", "two", "three", "four"][$0 - 1])" }
    let weeklyPairs = weeklyStrings.map { ["\($0)-a", "\($0)-b"] }
    let value: Any
    switch filename {
    case "comfort.json", "mindful.json", "international.json":
        value = ["cadence": "weekly", "data": weeklyStrings]
    case "sides.json", "soup.json":
        value = ["cadence": "weekly", "data": weeklyPairs]
    case "special.json":
        value = [Array(repeating: "special-one", count: 5),
                 Array(repeating: "special-two", count: 5)]
    default:
        value = [:]
    }
    return try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}
