import Foundation

/// Assembles the lunch manifest from the per-station files the website
/// publishes under `src/data/lunch-rotating`, with the same last-good-cache
/// guarantee used by schedule syncing: nothing replaces the cache unless every
/// station was fetched and the combined manifest validated.
public actor LunchMenuSyncService {
    public static let throttleInterval: TimeInterval = 3600

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
        // Six documents have no single entity tag between them, so the lunch
        // path does not make conditional requests; freshness comes from
        // comparing the assembled bytes. Clear any tag a previous build stored
        // for the retired single-manifest endpoint.
        metadata.etag = nil

        do {
            let data = try await fetchManifest()
            // Parsing is the gate: a manifest that does not validate never
            // reaches the cache, so the last known-good menu survives.
            _ = try LunchMenuParser.parse(data)
            let changed = data != store.cachedLunchMenuData
            metadata.lastSuccess = now
            metadata.lastError = nil
            if changed {
                metadata.lastChanged = now
                store.cachedLunchMenuData = data
            }
            store.lunchFetchMetadata = metadata
            return changed ? .updated : .notModified
        } catch {
            let message = (error as? LunchMenuParserError)?.description ?? error.localizedDescription
            metadata.lastError = message
            store.lunchFetchMetadata = metadata
            return .failed(message)
        }
    }

    /// Fetches every station at once and folds the results into the manifest
    /// shape the parser reads. The bundled manifest supplies only the rotation
    /// metadata the website does not publish — `validFrom`, `validTo`,
    /// `semesterSwitch` and `offset`. Every station value comes from the live
    /// files, and one failed or oversized station fails the whole refresh.
    private func fetchManifest() async throws -> Data {
        let session = self.session
        var payloads: [String: Data] = [:]
        try await withThrowingTaskGroup(of: (String, Data).self) { group in
            for name in SharedStore.lunchStationNames {
                let url = SharedStore.lunchStationURL(named: name)
                group.addTask {
                    // Streamed rather than buffered: six sources fetched at
                    // once, each read whole, is six unbounded allocations if an
                    // endpoint misbehaves. `collectBody` stops reading the
                    // moment one goes over the limit.
                    let (byteStream, response) = try await session.bytes(from: url)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw LunchMenuParserError.invalid(
                            "lunch source \(name) returned HTTP \(status)")
                    }
                    let data = try await Self.collectBody(byteStream, limit: LunchMenuParser.maxBytes)
                    return (name, data)
                }
            }
            for try await (name, data) in group {
                payloads[name] = data
            }
        }

        guard var manifest = try JSONSerialization.jsonObject(
            with: LunchMenuParser.bundledData()) as? [String: Any] else {
            throw LunchMenuParserError.invalid("bundled lunch manifest is not an object")
        }
        var stations: [String: Any] = [:]
        for name in SharedStore.lunchStationNames {
            guard let data = payloads[name] else {
                throw LunchMenuParserError.invalid("lunch source \(name) is missing")
            }
            let value = try JSONSerialization.jsonObject(with: data)
            // `special` is a top-level array of semesters, not a station.
            if name == "special" {
                manifest["special"] = value
            } else {
                stations[name] = value
            }
        }
        manifest["stations"] = stations
        // Sorted keys so a byte comparison against the cache reflects content
        // changes rather than dictionary ordering.
        return try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    }

    /// Size of the staging buffer `collectBody` fills before appending to the
    /// result. `Data.append(_: UInt8)` is far more expensive per call than
    /// appending to an array, and six stations stream in parallel, so the bytes
    /// are batched instead of pushed into `Data` one at a time.
    private static let collectChunkSize = 16 * 1024

    /// Reads the whole body but stops the moment it goes past `limit`, so a
    /// misbehaving endpoint cannot make the app buffer an unbounded response.
    /// The check runs per chunk rather than per byte, so at most one extra
    /// chunk beyond the limit is held before the throw.
    private static func collectBody(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        var chunk = [UInt8]()
        chunk.reserveCapacity(collectChunkSize)
        for try await byte in bytes {
            chunk.append(byte)
            if chunk.count == collectChunkSize {
                data.append(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
                if data.count > limit {
                    throw LunchMenuParserError.tooLarge(bytes: data.count)
                }
            }
        }
        data.append(contentsOf: chunk)
        if data.count > limit {
            throw LunchMenuParserError.tooLarge(bytes: data.count)
        }
        return data
    }
}
