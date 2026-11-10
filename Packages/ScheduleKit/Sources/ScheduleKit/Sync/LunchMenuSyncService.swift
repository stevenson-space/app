import Foundation

/// Fetches the lunch menus from the website's API with the same last-good-cache
/// guarantee as schedule syncing: nothing replaces the cache unless the
/// response parses and validates.
public actor LunchMenuSyncService {
    public static let throttleInterval: TimeInterval = 3600

    private let store: SharedStore
    private let session: URLSession

    public init(store: SharedStore, session: URLSession? = nil) {
        self.store = store
        self.session = session ?? ScheduleSyncService.makeSession()
    }

    /// Whether an automatic check should wait. Only a menu that can be shown
    /// earns the wait: after a first launch that failed, or an update from a
    /// version whose cache this one cannot read, the next activation retries.
    public static func isThrottled(_ metadata: FetchMetadata, hasMenu: Bool, at now: Date) -> Bool {
        hasMenu && metadata.isThrottled(at: now, interval: throttleInterval)
    }

    @discardableResult
    public func refresh(force: Bool, now: Date = Date()) async -> SyncResult {
        var metadata = store.lunchFetchMetadata
        let cached = store.cachedLunchMenuData
        let cachedMenu = LunchMenuLoader.load(cachedData: cached)
        if !force, Self.isThrottled(metadata, hasMenu: cachedMenu != nil, at: now) {
            return .skippedThrottled
        }

        metadata.recordAttempt(at: now)
        store.lunchFetchMetadata = metadata

        var request = URLRequest(url: SharedStore.lunchMenuURL)
        // A 304 answers "what you hold is current", so only ask that way while
        // holding a menu this version can read.
        let conditionalETag = cachedMenu == nil ? nil : metadata.etag
        if let conditionalETag {
            request.setValue(conditionalETag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (byteStream, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            switch http.statusCode {
            case 304 where conditionalETag != nil:
                metadata.lastSuccess = now
                metadata.lastError = nil
                store.lunchFetchMetadata = metadata
                return .notModified

            case 200:
                // Bound the body before materializing it: abort as soon as the
                // stream exceeds the parser's limit instead of buffering it all.
                let data = try await byteStream.collectBody(
                    limit: LunchMenuParser.maxBytes, tooLarge: LunchMenuParserError.tooLarge)
                // Parsing is the gate: a response that does not validate never
                // reaches the cache, so the last known-good menus survive.
                let menu = try LunchMenuParser.parse(data)
                // The payload is restamped by every site build. Compare the
                // menus, which do change daily as the window slides forward.
                let changed = menu != cachedMenu
                metadata.lastSuccess = now
                metadata.lastError = nil
                metadata.etag = http.value(forHTTPHeaderField: "ETag")
                if changed { metadata.lastChanged = now }
                // Stored even when only the stamp moved, so the cache is always
                // the payload the ETag above describes.
                if data != cached { store.cachedLunchMenuData = data }
                store.lunchFetchMetadata = metadata
                return changed ? .updated : .notModified

            default:
                // Includes a 304 to a request that was not conditional (a
                // captive portal or a misbehaving proxy), which confirms nothing.
                metadata.lastError = "HTTP \(http.statusCode)"
                store.lunchFetchMetadata = metadata
                return .failed("HTTP \(http.statusCode)")
            }
        } catch {
            let message = (error as? LunchMenuParserError)?.description ?? error.localizedDescription
            metadata.lastError = message
            store.lunchFetchMetadata = metadata
            return .failed(message)
        }
    }
}
