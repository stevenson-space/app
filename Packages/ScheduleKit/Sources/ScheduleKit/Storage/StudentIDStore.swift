import Foundation

/// Errors surfaced by `StudentIDStore`. Underlying filesystem details are not
/// included in the enum so callers do not accidentally present private paths
/// to a user; the localized description remains useful for diagnostics.
public enum StudentIDStoreError: Error, Equatable, Sendable {
    case invalidProfile(StudentIDProfileValidationError)
    case invalidStoredData
    case unableToRead
    case unableToWrite
    case unableToDelete
}

extension StudentIDStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidProfile(let reason):
            return reason.localizedDescription
        case .invalidStoredData:
            return "The saved student-ID profile could not be read."
        case .unableToRead:
            return "The saved student-ID profile could not be accessed."
        case .unableToWrite:
            return "The student-ID profile could not be saved."
        case .unableToDelete:
            return "The saved student-ID profile could not be removed."
        }
    }
}

/// A small, single-record file store for `StudentIDProfile`.
///
/// The URL is injectable to keep tests isolated and to let the app choose its
/// Application Support location. Writes use Foundation's atomic option. On
/// iOS, the resulting file receives complete file protection as well.
public final class StudentIDStore: @unchecked Sendable {
    public static let defaultFileName = "student-id-profile.json"

    public let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    /// Creates a store at an explicit file URL. The parent directory is
    /// created lazily on the first save.
    public init(fileURL: URL,
                fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        // Foundation's default Date representation preserves sub-second
        // metadata exactly.
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Uses Application Support rather than Documents so the profile is not
    /// user-visible file-sharing content. The app may still inject a URL in
    /// tests or in an alternate host target.
    public convenience init(fileManager: FileManager = .default) {
        let root = fileManager.urls(for: .applicationSupportDirectory,
                                    in: .userDomainMask).first ??
            fileManager.temporaryDirectory
        let directory = root.appendingPathComponent("Stevenson Space Companion App",
                                                     isDirectory: true)
        self.init(fileURL: directory.appendingPathComponent(Self.defaultFileName),
                  fileManager: fileManager)
    }

    /// Reads and validates the one persisted profile. A missing file means no
    /// profile has been set up yet and is represented by `nil`.
    public func load() throws -> StudentIDProfile? {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            throw StudentIDStoreError.unableToRead
        }

        do {
            let profile = try decoder.decode(StudentIDProfile.self, from: data)
            try profile.validate()
            return profile
        } catch let error as StudentIDProfileValidationError {
            throw StudentIDStoreError.invalidProfile(error)
        } catch {
            throw StudentIDStoreError.invalidStoredData
        }
    }

    /// Validates before serializing, creates the parent directory, and then
    /// atomically replaces the previous profile. The source scan image is not
    /// accepted by this API and consequently cannot be written here.
    @discardableResult
    public func save(_ profile: StudentIDProfile) throws -> StudentIDProfile {
        do {
            try profile.validate()
        } catch let error as StudentIDProfileValidationError {
            throw StudentIDStoreError.invalidProfile(error)
        } catch {
            throw StudentIDStoreError.invalidProfile(.invalidMetadata)
        }

        lock.lock()
        defer { lock.unlock() }

        let data: Data
        do {
            data = try encoder.encode(profile)
        } catch {
            throw StudentIDStoreError.unableToWrite
        }

        do {
            let parent = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent,
                                             withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700],
                                          ofItemAtPath: parent.path)

            #if os(iOS) || os(tvOS) || os(watchOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: parent.path)
            try data.write(to: fileURL,
                           options: [.atomic, .completeFileProtection])
            // `.completeFileProtection` is honored by Data on supported OSes;
            // setting the attribute explicitly also covers replacement files.
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: fileURL.path)
            #else
            try data.write(to: fileURL, options: [.atomic])
            #endif
            try fileManager.setAttributes([.posixPermissions: 0o600],
                                          ofItemAtPath: fileURL.path)
        } catch {
            throw StudentIDStoreError.unableToWrite
        }

        return profile
    }

    /// Removes the profile if it exists. Deleting an already-empty store is a
    /// successful no-op, which keeps reset actions idempotent.
    public func delete() throws {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw StudentIDStoreError.unableToDelete
        }
    }

    public var exists: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fileManager.fileExists(atPath: fileURL.path)
    }
}
