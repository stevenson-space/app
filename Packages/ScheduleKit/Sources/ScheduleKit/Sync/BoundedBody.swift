import Foundation

extension URLSession.AsyncBytes {
    /// Size of the staging buffer `collectBody` fills before appending to the
    /// result. `Data.append(_: UInt8)` is far more expensive per call than
    /// appending to an array, and the lunch stations stream in parallel, so the
    /// bytes are batched instead of pushed into `Data` one at a time.
    private static var collectChunkSize: Int { 16 * 1024 }

    /// Reads the whole body but stops the moment it goes past `limit`, so a
    /// misbehaving endpoint cannot make the app buffer an unbounded response.
    /// The check runs per chunk rather than per byte, so at most one extra
    /// chunk beyond the limit is held before throwing `tooLarge(byteCount)`.
    func collectBody(limit: Int, tooLarge: (Int) -> any Error) async throws -> Data {
        var data = Data()
        var chunk = [UInt8]()
        chunk.reserveCapacity(Self.collectChunkSize)
        for try await byte in self {
            chunk.append(byte)
            if chunk.count == Self.collectChunkSize {
                data.append(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
                if data.count > limit {
                    throw tooLarge(data.count)
                }
            }
        }
        data.append(contentsOf: chunk)
        if data.count > limit {
            throw tooLarge(data.count)
        }
        return data
    }
}
