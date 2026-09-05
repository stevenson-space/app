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
        // Encrypted at rest, but readable from the first unlock onward — a
        // student pulling up their ID at a lunch line should never meet a card
        // that will not load. Complete protection would do exactly that.
        try jpeg.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try jpeg.write(to: url, options: [.atomic])
        #endif
        return url
    }

    public func loadData() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
