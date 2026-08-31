import Foundation

/// Fetches the website's consolidated lunch manifest with the same conditional
/// request and last-good-cache guarantees used by schedule syncing.
public actor LunchMenuSyncService {
    public static let throttleInterval: TimeInterval = 3600

    private struct LegacySource: Sendable {
        let key: String
        let url: URL
    }

    private static let legacySources: [LegacySource] = {
        let root = "https://raw.githubusercontent.com/stevenson-space/shs/main/src/data/lunch-rotating"
        return ["comfort", "mindful", "sides", "soup", "international", "special"].map {
            LegacySource(key: $0, url: URL(string: "\(root)/\($0).json")!)
        }
    }()

    private let store: SharedStore
    private let session: URLSession

    public init(store: SharedStore, session: URLSession? = nil) {
        self.store = store
        self.session = session ?? ScheduleSyncService.makeSession()
    }

    @discardableResult
    public func refresh(force: Bool, now: Date = Date()) async -> SyncResult {
        var metadata = store.lunchFetchMetadata
        if !force, let lastAttempt = metadata.lastAttempt,
           now.timeIntervalSince(lastAttempt) < Self.throttleInterval,
           now.timeIntervalSince(lastAttempt) >= 0 {
            return .skippedThrottled
        }

        metadata.lastAttempt = now
        var request = URLRequest(url: SharedStore.defaultLunchMenuURL)
        if let etag = metadata.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        do {
            let (byteStream, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            switch http.statusCode {
            case 304:
                guard store.cachedLunchMenuData != nil else {
                    metadata.etag = nil
                    store.lunchFetchMetadata = metadata
                    return await refresh(force: true, now: now)
                }
                metadata.lastSuccess = now
                metadata.lastError = nil
                store.lunchFetchMetadata = metadata
                return .notModified

            case 200:
                let data = try await collectBody(byteStream, limit: LunchMenuParser.maxBytes)
                return try commit(data, etag: http.value(forHTTPHeaderField: "ETag"),
                                  metadata: &metadata, now: now)

            case 404:
                // The website historically stores each station in its own raw
                // file. This path works without a website change; once the
                // consolidated manifest is published, the 200 path above takes
                // over automatically.
                let data = try await fetchLegacyManifest()
                return try commit(data, etag: nil, metadata: &metadata, now: now)

            default:
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

    private func commit(_ data: Data, etag: String?, metadata: inout FetchMetadata,
                        now: Date) throws -> SyncResult {
        _ = try LunchMenuParser.parse(data)
        let changed = data != store.cachedLunchMenuData
        metadata.lastSuccess = now
        metadata.lastError = nil
        metadata.etag = etag
        if changed {
            metadata.lastChanged = now
            store.cachedLunchMenuData = data
        }
        store.lunchFetchMetadata = metadata
        return changed ? .updated : .notModified
    }

    /// Builds the consolidated schema from the six raw files the website has
    /// served for years. The bundled manifest supplies only rotation dates and
    /// offset; every station value comes from the live website sources.
    private func fetchLegacyManifest() async throws -> Data {
        let session = self.session
        var payloads: [String: Data] = [:]
        try await withThrowingTaskGroup(of: (String, Data).self) { group in
            for source in Self.legacySources {
                group.addTask {
                    let (data, response) = try await session.data(from: source.url)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw LunchMenuParserError.invalid(
                            "legacy lunch source \(source.key) returned HTTP \(status)")
                    }
                    guard data.count <= LunchMenuParser.maxBytes else {
                        throw LunchMenuParserError.tooLarge(bytes: data.count)
                    }
                    return (source.key, data)
                }
            }
            for try await (key, data) in group {
                payloads[key] = data
            }
        }

        guard var manifest = try JSONSerialization.jsonObject(
            with: LunchMenuParser.bundledData()) as? [String: Any] else {
            throw LunchMenuParserError.invalid("bundled lunch manifest is not an object")
        }
        var stations: [String: Any] = [:]
        for source in Self.legacySources {
            guard let data = payloads[source.key] else {
                throw LunchMenuParserError.invalid("legacy lunch source \(source.key) is missing")
            }
            let value = try JSONSerialization.jsonObject(with: data)
            if source.key == "special" {
                manifest["special"] = value
            } else {
                stations[source.key] = value
            }
        }
        manifest["stations"] = stations
        return try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    }

    private func collectBody(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit {
                throw LunchMenuParserError.tooLarge(bytes: data.count)
            }
        }
        return data
    }
}
