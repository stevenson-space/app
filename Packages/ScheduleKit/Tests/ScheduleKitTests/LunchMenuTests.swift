import Testing
import Foundation
@testable import ScheduleKit

@Suite struct LunchMenuParserTests {
    @Test func parsesTheAPISnapshot() throws {
        let menu = try LunchMenuParser.parse(TestSupport.fixture("lunch-api-v1"))

        let monday = try #require(menu.menu(for: day(2026, 11, 2)))
        #expect(monday.sections.map(\.station) == LunchMenuStation.allCases)
        #expect(items(.comfort, in: monday) == ["Vegetarian Paella"])
        #expect(items(.mindful, in: monday) == ["Baked Chicken Parmesan"])
        #expect(items(.sides, in: monday) == ["Roasted Broccolini", "Pasta"])
        #expect(items(.soup, in: monday) == ["Lasagna Soup", "Cream of Potato"])
        #expect(items(.international, in: monday) == ["Burrito Bowl"])
        // The website names the special after its weekday.
        #expect(items(.special, in: monday) == ["Sushi Monday"])
        let tuesday = try #require(menu.menu(for: day(2026, 11, 10)))
        #expect(items(.special, in: tuesday) == ["Tacos Tuesday"])

        // Only school days are published: election day, a weekend and the
        // Thanksgiving break are simply absent.
        #expect(menu.menu(for: day(2026, 11, 3)) == nil)
        #expect(menu.menu(for: day(2026, 11, 7)) == nil)
        #expect(menu.menu(for: day(2026, 11, 26)) == nil)
        // The window ends on the last published day.
        #expect(menu.lastDay == day(2026, 11, 30))
        #expect(menu.menu(for: day(2026, 12, 1)) == nil)
    }

    @Test func snapshotPlaceholderStationsAreLeftOffTheDay() throws {
        let menu = try LunchMenuParser.parse(TestSupport.fixture("lunch-api-v1"))

        // The kitchen has no comfort, mindful or sides plan for this Monday;
        // the API passes its "?? No Information" through.
        let monday = try #require(menu.menu(for: day(2026, 11, 16)))
        #expect(items(.comfort, in: monday) == nil)
        #expect(items(.mindful, in: monday) == nil)
        #expect(items(.sides, in: monday) == nil)
        #expect(items(.soup, in: monday) == ["Garden Vegetable Soup", "New England Clam Chowder"])
        #expect(items(.international, in: monday) == ["Mediterranean"])
        #expect(items(.special, in: monday) == ["Sushi Monday"])
    }

    @Test(arguments: [" ?? No Information ", " No Information ", " None Specified ", " TBD ", " no information ", " tbd ", "  "])
    func placeholderItemsAreDropped(placeholder: String) throws {
        let tuesday = day(2026, 9, 15)
        var dishes = TestSupport.lunchDishes(tuesday)
        dishes["comfort"] = placeholder
        dishes["sides"] = [placeholder, "Lemon Rice"]
        let menu = try LunchMenuParser.parse(TestSupport.lunchPayload(days: [(tuesday, dishes)]))

        let published = try #require(menu.menu(for: tuesday))
        #expect(items(.comfort, in: published) == nil)
        #expect(items(.sides, in: published) == ["Lemon Rice"])
        #expect(items(.mindful, in: published) == ["a-mindful-2026-09-15"])
    }

    @Test(arguments: [" ?? No Information ", " None Specified ", " TBD "])
    func aDayOfNothingButPlaceholdersHasNoMenu(placeholder: String) throws {
        let monday = day(2026, 9, 14)
        let dishes: [String: Any] = [
            "comfort": placeholder, "mindful": placeholder, "international": placeholder,
            "sides": [placeholder, placeholder], "soup": [placeholder, placeholder],
            "special": placeholder,
        ]
        let menu = try LunchMenuParser.parse(TestSupport.lunchPayload(days: [
            (monday, dishes),
            (monday.advanced(by: 1), TestSupport.lunchDishes(monday.advanced(by: 1))),
        ]))

        #expect(menu.menu(for: monday) == nil)
        #expect(LunchMenuLoader.menu(menu, for: monday,
                                     inputs: ResolverInputs(catalog: TestSupport.catalog)) == nil)
        // An unplanned day is not the end of the published menus.
        #expect(menu.lastDay == monday.advanced(by: 1))
    }

    @Test func dishNamesAreTrimmedBeforeDisplay() throws {
        let tuesday = day(2026, 9, 15)
        var dishes = TestSupport.lunchDishes(tuesday)
        dishes["comfort"] = " \tRoasted Chicken\n"
        let menu = try LunchMenuParser.parse(TestSupport.lunchPayload(days: [(tuesday, dishes)]))
        #expect(items(.comfort, in: try #require(menu.menu(for: tuesday))) == ["Roasted Chicken"])

        let snapshot = try LunchMenuParser.parse(TestSupport.fixture("lunch-api-v1"))
        let friday = try #require(snapshot.menu(for: day(2026, 11, 6)))
        #expect(items(.sides, in: friday) == ["Roasted Vegetables", "Maple Whipped Sweet Potatoes"])
    }

    @Test func theSpecialIsNamedAfterEachWeekday() throws {
        let menu = TestSupport.septemberLunchMenu
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        for (offset, name) in names.enumerated() {
            let published = try #require(menu.menu(for: day(2026, 9, 14 + offset)))
            #expect(items(.special, in: published) == ["a-special \(name)"])
        }
    }

    @Test func aStationCanServeOneDishOrSeveral() throws {
        let tuesday = day(2026, 9, 15)
        var dishes = TestSupport.lunchDishes(tuesday)
        dishes["comfort"] = ["Fried Chicken", "Veggie Burger"]
        dishes["soup"] = "Minestrone"
        let menu = try LunchMenuParser.parse(TestSupport.lunchPayload(days: [(tuesday, dishes)]))

        let published = try #require(menu.menu(for: tuesday))
        #expect(items(.comfort, in: published) == ["Fried Chicken", "Veggie Burger"])
        #expect(items(.soup, in: published) == ["Minestrone"])
    }

    @Test func stationsTheAppDoesNotKnowAreIgnored() throws {
        let tuesday = day(2026, 9, 15)
        var dishes = TestSupport.lunchDishes(tuesday)
        dishes["grill"] = ["name": "Burger", "price": 4] as [String: Any]
        dishes["soup"] = nil
        let menu = try LunchMenuParser.parse(TestSupport.lunchPayload(days: [(tuesday, dishes)]))

        // A station the API adds, or stops sending, costs only that station.
        let published = try #require(menu.menu(for: tuesday))
        #expect(published.sections.map(\.station) == [.comfort, .mindful, .sides, .international, .special])
    }

    @Test func anEmptyWindowIsAMenuWithNoDays() throws {
        // What the API serves once its window leaves the menu data's range,
        // as it does over the summer.
        let summer = Data(#"""
            {"version": 1, "window": {"start": null, "end": null, "refreshAfter": "2027-07-20"},
             "validRange": {"start": "2026-08-10", "end": "2027-05-31"}, "days": []}
            """#.utf8)
        let menu = try LunchMenuParser.parse(summer)
        #expect(menu.lastDay == nil)
        #expect(menu.menu(for: day(2027, 6, 14)) == nil)
    }

    @Test func malformedPayloadsFailWholesale() throws {
        let tuesday = day(2026, 9, 15)
        func payload(date: String, menu: Any) -> Data {
            try! JSONSerialization.data(withJSONObject: ["days": [["date": date, "menu": menu]]])
        }
        let malformed: [Data] = [
            Data("not json".utf8),
            // What the site serves for a path it does not have.
            Data("<!doctype html><html><body>Stevenson Space</body></html>".utf8),
            Data("{}".utf8),
            Data(#"{"days": {"2026-09-15": {}}}"#.utf8),
            payload(date: "9/15/2026", menu: TestSupport.lunchDishes(tuesday)),
            payload(date: "2026-02-30", menu: TestSupport.lunchDishes(tuesday)),
            payload(date: "2026-09-15", menu: ["comfort": 7]),
            payload(date: "2026-09-15", menu: ["sides": ["Rice", 7] as [Any]]),
            Data(#"{"days": [{"date": "2026-09-15"}]}"#.utf8),
            Data(repeating: 0x20, count: LunchMenuParser.maxBytes + 1),
        ]
        for data in malformed {
            #expect(throws: LunchMenuParserError.self) { _ = try LunchMenuParser.parse(data) }
        }
    }

    @Test func aRotationManifestFromAnEarlierVersionIsNotAMenu() {
        // Versions before the API cached the rotation itself. It cannot be
        // read as published days, so it loads as no menu until the next refresh.
        #expect(throws: LunchMenuParserError.self) { _ = try LunchMenuParser.parse(legacyRotationManifest) }
        #expect(LunchMenuLoader.load(cachedData: legacyRotationManifest) == nil)
    }
}

@Suite(.serialized) struct LunchMenuSyncTests {
    private let monday = day(2026, 9, 14)
    private var mondayPayload: Data {
        TestSupport.lunchPayload(from: day(2026, 9, 7), through: day(2026, 10, 5))
    }

    @Test func fetchesTheMenusFromTheWebsiteAPI() async throws {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        let body = mondayPayload
        LunchStubURLProtocol.handler = { _ in (200, ["ETag": "\"monday\""], body) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        #expect(await service.refresh(force: true, now: now) == .updated)

        // One document, where the old source needed six.
        let requests = LunchStubURLProtocol.requests
        #expect(requests.map(\.url?.absoluteString) == ["https://stevenson.space/api/v1/lunch.json"])
        #expect(requests.first?.value(forHTTPHeaderField: "If-None-Match") == nil)

        #expect(store.cachedLunchMenuData == body)
        let menu = try #require(LunchMenuLoader.load(cachedData: store.cachedLunchMenuData))
        let published = try #require(menu.menu(for: monday))
        #expect(published.sections.first { $0.station == .comfort }?.items == ["a-comfort-2026-09-14"])
        #expect(published.sections.first { $0.station == .soup }?.items
                == ["a-soup-2026-09-14-a", "a-soup-2026-09-14-b"])

        #expect(store.lunchFetchMetadata.lastSuccess == now)
        #expect(store.lunchFetchMetadata.lastChanged == now)
        #expect(store.lunchFetchMetadata.lastError == nil)
        #expect(store.lunchFetchMetadata.etag == "\"monday\"")
    }

    @Test func aLaterCheckIsConditionalAndA304KeepsTheMenus() async throws {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        let body = mondayPayload
        LunchStubURLProtocol.handler = { request in
            request.value(forHTTPHeaderField: "If-None-Match") == "\"monday\""
                ? (304, [:], Data()) : (200, ["ETag": "\"monday\""], body)
        }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        let first = Date(timeIntervalSince1970: 1_900_000_000)
        #expect(await service.refresh(force: true, now: first) == .updated)

        // An overdue check clears the reminder even when the menus are unchanged.
        let later = SchoolTime.calendar.date(byAdding: .day, value: 8, to: first)!
        #expect(store.lunchFetchMetadata.isUpdateCheckOverdue(at: later))
        #expect(await service.refresh(force: true, now: later) == .notModified)

        #expect(LunchStubURLProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"monday\"")
        #expect(store.cachedLunchMenuData == body)
        #expect(store.lunchFetchMetadata.lastChanged == first)
        #expect(store.lunchFetchMetadata.lastSuccess == later)
        #expect(!store.lunchFetchMetadata.isUpdateCheckOverdue(at: later))
    }

    @Test func aRebuildWithTheSameMenusIsNotModified() async throws {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        let body = mondayPayload
        LunchStubURLProtocol.handler = { _ in (200, ["ETag": "\"monday\""], body) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        let first = Date(timeIntervalSince1970: 1_900_000_000)
        #expect(await service.refresh(force: true, now: first) == .updated)

        // The site was redeployed the same day: a new stamp and ETag around
        // the same menus.
        let redeployed = TestSupport.lunchPayload(from: day(2026, 9, 7), through: day(2026, 10, 5),
                                                  generatedAt: "2026-09-14T15:02:41.118Z")
        #expect(redeployed != body)
        LunchStubURLProtocol.handler = { _ in (200, ["ETag": "\"redeploy\""], redeployed) }
        #expect(await service.refresh(force: true, now: first + 60) == .notModified)

        #expect(store.lunchFetchMetadata.lastChanged == first)
        #expect(store.lunchFetchMetadata.lastSuccess == first + 60)
        // The cache follows the ETag, so a later 304 refers to what is held.
        #expect(store.lunchFetchMetadata.etag == "\"redeploy\"")
        #expect(store.cachedLunchMenuData == redeployed)
    }

    @Test func theSlidingWindowReplacesTheCachedMenus() async throws {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        let body = mondayPayload
        LunchStubURLProtocol.handler = { _ in (200, [:], body) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        let first = Date(timeIntervalSince1970: 1_900_000_000)
        #expect(await service.refresh(force: true, now: first) == .updated)

        // Overnight the window moves a day: one old menu drops off the back
        // and a new one appears at the front.
        let tuesdayPayload = TestSupport.lunchPayload(from: day(2026, 9, 8), through: day(2026, 10, 6),
                                                      generatedAt: "2026-09-15T07:44:10.201Z")
        LunchStubURLProtocol.handler = { _ in (200, [:], tuesdayPayload) }
        #expect(await service.refresh(force: true, now: first + 86_400) == .updated)

        #expect(store.lunchFetchMetadata.lastChanged == first + 86_400)
        let menu = try #require(LunchMenuLoader.load(cachedData: store.cachedLunchMenuData))
        #expect(menu.menu(for: day(2026, 9, 7)) == nil)
        #expect(menu.menu(for: day(2026, 10, 6)) != nil)
        #expect(menu.lastDay == day(2026, 10, 6))
    }

    @Test func aCacheFromAnEarlierVersionIsReplacedWithoutWaiting() async throws {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        // An install updated minutes after its last check: a rotation manifest
        // in the cache, a tag for it, and a throttle window still open.
        store.cachedLunchMenuData = legacyRotationManifest
        store.lunchFetchMetadata = FetchMetadata(lastAttempt: now - 600, lastSuccess: now - 600,
                                                 etag: "\"rotation\"")
        LunchStubURLProtocol.reset()
        let body = mondayPayload
        LunchStubURLProtocol.handler = { _ in (200, ["ETag": "\"monday\""], body) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())

        // Not throttled: there is no menu to show in the meantime.
        #expect(await service.refresh(force: false, now: now) == .updated)

        // And not conditional: a 304 would vouch for a cache that cannot be read.
        #expect(LunchStubURLProtocol.requests.map { $0.value(forHTTPHeaderField: "If-None-Match") } == [nil])
        #expect(store.cachedLunchMenuData == body)
        #expect(store.lunchFetchMetadata.etag == "\"monday\"")
    }

    @Test func aFailedFirstFetchIsRetriedOnTheNextActivation() async {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        LunchStubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        guard case .failed = await service.refresh(force: false, now: now) else {
            Issue.record("Expected the offline fetch to fail")
            return
        }

        // No menu ships with the app, so waiting out the throttle would leave
        // the Lunch tab empty for an hour after one bad connection.
        let body = mondayPayload
        LunchStubURLProtocol.handler = { _ in (200, [:], body) }
        #expect(await service.refresh(force: false, now: now + 60) == .updated)
        #expect(store.cachedLunchMenuData == body)
    }

    @Test func a304ToAnUnconditionalRequestFails() async {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        LunchStubURLProtocol.handler = { _ in (304, [:], Data()) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())

        #expect(await service.refresh(force: true) == .failed("HTTP 304"))
        #expect(LunchStubURLProtocol.requests.count == 1)
        #expect(store.cachedLunchMenuData == nil)
        #expect(store.lunchFetchMetadata.lastSuccess == nil)
        #expect(store.lunchFetchMetadata.lastError == "HTTP 304")
    }

    @Test(arguments: [
        (200, Data("<!doctype html><html><body>Stevenson Space</body></html>".utf8)),
        (200, Data(#"{"days": [{"date": "soon", "menu": {}}]}"#.utf8)),
        (500, Data()),
        (404, Data()),
    ])
    func aBadResponseKeepsTheLastGoodMenus(status: Int, body: Data) async throws {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        let good = mondayPayload
        LunchStubURLProtocol.handler = { _ in (200, [:], good) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        let first = Date(timeIntervalSince1970: 1_900_000_000)
        #expect(await service.refresh(force: true, now: first) == .updated)

        LunchStubURLProtocol.handler = { _ in (status, [:], body) }
        guard case .failed = await service.refresh(force: true, now: first + 20) else {
            Issue.record("Expected HTTP \(status) to fail the refresh")
            return
        }
        #expect(store.cachedLunchMenuData == good)
        #expect(store.lunchFetchMetadata.lastError != nil)
        #expect(store.lunchFetchMetadata.lastChanged == first)
        #expect(store.lunchFetchMetadata.lastSuccess == first)
    }

    @Test(arguments: [false, true])
    func offlineRetriesPreserveTheFirstAttemptAcrossLaunches(legacy: Bool) async {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = TestSupport.at(day(2026, 9, 1), 12, 0)
        let later = TestSupport.at(day(2026, 9, 9), 12, 0)
        if legacy {
            store.lunchFetchMetadata = FetchMetadata(lastAttempt: first, lastError: "Offline")
        }
        LunchStubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        if !legacy {
            let service = LunchMenuSyncService(store: store, session: makeStubSession())
            _ = await service.refresh(force: false, now: first)
            #expect(!store.lunchFetchMetadata.isUpdateCheckOverdue(at: first))
        }

        let reopenedStore = SharedStore(defaults: defaults, secrets: InMemorySecretStore())
        let service = LunchMenuSyncService(store: reopenedStore, session: makeStubSession())
        _ = await service.refresh(force: false, now: later)
        #expect(reopenedStore.lunchFetchMetadata.firstAttempt == first)
        #expect(reopenedStore.lunchFetchMetadata.lastSuccess == nil)
        #expect(reopenedStore.lunchFetchMetadata.isUpdateCheckOverdue(at: later))
    }

    @Test func throttleSkipsRecentAttemptsUnlessForced() async {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        let body = mondayPayload
        LunchStubURLProtocol.handler = { _ in (200, [:], body) }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        #expect(await service.refresh(force: true, now: now) == .updated)
        LunchStubURLProtocol.reset()

        // A foreground activation minutes later must not fetch again.
        #expect(await service.refresh(force: false, now: now + 60) == .skippedThrottled)
        #expect(LunchStubURLProtocol.requests.isEmpty)

        // Pull-to-refresh bypasses the window.
        #expect(await service.refresh(force: true, now: now + 60) == .notModified)
        #expect(LunchStubURLProtocol.requests.count == 1)

        // So does an activation past the window, measured from that forced
        // attempt rather than from the first one.
        LunchStubURLProtocol.reset()
        let pastWindow = now + 60 + LunchMenuSyncService.throttleInterval + 1
        #expect(await service.refresh(force: false, now: pastWindow) == .notModified)
        #expect(LunchStubURLProtocol.requests.count == 1)
    }

    @Test func anOversizedResponseIsRejected() async {
        let (store, defaults, suite) = makeLunchStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        LunchStubURLProtocol.reset()
        // An endpoint serving an endless body must be cut off mid-stream, not
        // buffered whole.
        LunchStubURLProtocol.handler = { _ in
            (200, [:], Data(repeating: 0x20, count: LunchMenuParser.maxBytes * 4))
        }
        let service = LunchMenuSyncService(store: store, session: makeStubSession())

        guard case .failed = await service.refresh(force: true) else {
            Issue.record("Expected an oversized response to fail")
            return
        }
        #expect(store.cachedLunchMenuData == nil)
    }
}

private func items(_ station: LunchMenuStation, in menu: LunchMenuDay) -> [String]? {
    menu.sections.first { $0.station == station }?.items
}

/// The shape versions before the API cached under the same key: the website's
/// rotation, which those versions resolved to dates themselves.
let legacyRotationManifest: Data = {
    let weekly = ["cadence": "weekly", "data": ["week-0", "week-1"]] as [String: Any]
    let pairs = ["cadence": "weekly", "data": [["a", "b"], ["c", "d"]]] as [String: Any]
    let object: [String: Any] = [
        "validFrom": "2026-08-10",
        "validTo": "2027-05-31",
        "semesterSwitch": "2027-01-01",
        "offset": 0,
        "stations": ["comfort": weekly, "mindful": weekly, "sides": pairs, "soup": pairs,
                     "international": weekly],
        "special": [Array(repeating: "Sushi", count: 5), Array(repeating: "Tacos", count: 5)],
    ]
    return try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}()

private final class LunchStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (Int, [String: String], Data))?
    /// Handlers run on URLSession's queue, so recording is locked.
    private nonisolated(unsafe) static var recorded: [URLRequest] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock()
        recorded = []
        lock.unlock()
    }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        Self.lock.unlock()
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
