import Foundation

public enum SyncResult: Equatable, Sendable {
    /// New content validated and committed to the cache.
    case updated
    /// Server reached; content unchanged (304 or byte-identical 200).
    case notModified
    /// Skipped because a recent attempt exists and `force` was false.
    case skippedThrottled
    /// Network/HTTP/parse failure. The last-good cache is untouched.
    case failed(String)
}

/// Fetches the remote day-type map with conditional requests and last-good
/// semantics: nothing is ever committed unless it parses and validates, so a
/// bad deploy of the JSON can never take out users' cached schedules.
public actor ScheduleSyncService {
    public static let throttleInterval: TimeInterval = 3600

    private let store: SharedStore
    private let session: URLSession

    public init(store: SharedStore, session: URLSession? = nil) {
        self.store = store
        self.session = session ?? Self.makeSession()
    }

    /// Plain session: no URL cache (conditional requests are handled manually
    /// via the stored ETag, so behavior is explicit and testable).
    public static func makeSession(protocolClasses: [AnyClass]? = nil) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        if let protocolClasses {
            config.protocolClasses = protocolClasses
        }
        return URLSession(configuration: config)
    }

    @discardableResult
    public func refresh(force: Bool, now: Date = Date()) async -> SyncResult {
        var metadata = store.fetchMetadata

        if !force, let lastAttempt = metadata.lastAttempt,
           now.timeIntervalSince(lastAttempt) < Self.throttleInterval,
           now.timeIntervalSince(lastAttempt) >= 0 {
            return .skippedThrottled
        }

        metadata.lastAttempt = now

        var request = URLRequest(url: store.mapURL)
        if let etag = metadata.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            switch http.statusCode {
            case 304:
                metadata.lastSuccess = now
                metadata.lastError = nil
                store.fetchMetadata = metadata
                return .notModified

            case 200:
                // Validate before committing — this is the last-good guarantee.
                _ = try ScheduleDatesParser.parse(data)
                let changed = data != store.cachedMapData
                metadata.lastSuccess = now
                metadata.lastError = nil
                metadata.etag = http.value(forHTTPHeaderField: "ETag")
                if changed {
                    metadata.lastChanged = now
                    store.cachedMapData = data
                }
                store.fetchMetadata = metadata
                return changed ? .updated : .notModified

            default:
                metadata.lastError = "HTTP \(http.statusCode)"
                store.fetchMetadata = metadata
                return .failed("HTTP \(http.statusCode)")
            }
        } catch {
            let message = (error as? ParserError)?.description ?? error.localizedDescription
            metadata.lastError = message
            store.fetchMetadata = metadata
            return .failed(message)
        }
    }
}
