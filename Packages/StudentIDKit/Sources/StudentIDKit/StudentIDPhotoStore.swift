import Foundation

/// Stores the cropped headshot as a file.
///
/// It lives in the app's own container, not the App Group container, because the
/// project has no App Group entitlement yet (see the note in ScheduleKit's
/// `SharedStore`). When widgets arrive and the entitlement lands, move this
/// directory into the group container so other surfaces can show the card too.
///
/// The source screenshot is never written anywhere — only this crop and the
/// handful of extracted fields.
public struct StudentIDPhotoStore: Sendable {
    private let directory: URL
    private static let fileName = "student-id-photo.jpg"

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("StudentID", isDirectory: true)
        }
    }

    public var fileURL: URL {
        directory.appendingPathComponent(StudentIDPhotoStore.fileName)
    }

    @discardableResult
    public func save(_ jpeg: Data) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL
        #if os(iOS)
        // The strongest class available: the file is unreadable whenever the
        // screen is locked. The card is only ever shown in the foreground, on an
        // unlocked device, so the student at the lunch line never notices — but
        // a launch while locked will read nothing, which is why `loadData`
        // distinguishes "no photo" from "not yet".
        try jpeg.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try jpeg.write(to: url, options: [.atomic])
        #endif
        return url
    }

    /// What a read found — a locked device is not an absent photo, and deleting
    /// on the strength of one would throw away the student's ID picture.
    public enum LoadResult: Sendable {
        case value(Data)
        case missing
        /// The file is there but protected; try again once the device unlocks.
        case unavailable
    }

    public func load() -> LoadResult {
        if let data = try? Data(contentsOf: fileURL) { return .value(data) }
        // Existence is readable while locked even when the contents are not.
        return FileManager.default.fileExists(atPath: fileURL.path) ? .unavailable : .missing
    }

    public func loadData() -> Data? {
        if case let .value(data) = load() { return data }
        return nil
    }

    public func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
