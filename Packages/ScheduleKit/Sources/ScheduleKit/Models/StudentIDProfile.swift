import Foundation

/// The only student-ID information persisted by the app.
///
/// A profile deliberately has no field for the image used during scanning.
/// Callers may keep a cropped portrait JPEG when the user chooses to do so,
/// but the original card/photo is never part of this value or the store
/// format.
public struct StudentIDProfile: Codable, Equatable, Hashable, Sendable {
    /// Student numbers outside this range are not accepted by the scanner or
    /// by the persistent store. Four digits is the shortest useful value for
    /// this school, while the upper bound prevents accidentally persisting an
    /// arbitrary barcode payload.
    public static let supportedStudentNumberLengths = 4...12

    /// A display name is user-facing text, so keep a malformed OCR payload or
    /// an unexpectedly large pasted value from becoming persistent state.
    public static let maxDisplayNameLength = 120

    /// A portrait is intentionally small and optional. The scanner crops and
    /// JPEG-encodes before creating a profile; this cap also protects callers
    /// that construct one directly.
    public static let maxPortraitJPEGBytes = 5 * 1024 * 1024

    public var studentNumber: String
    public var displayName: String?
    public var portraitJPEGData: Data?
    public var createdAt: Date
    public var updatedAt: Date

    /// Creates a profile. Validation is explicit so decoding and UI form
    /// state can represent invalid input without trapping; `StudentIDStore`
    /// validates before it writes.
    public init(studentNumber: String,
                displayName: String? = nil,
                portraitJPEGData: Data? = nil,
                createdAt: Date = Date(),
                updatedAt: Date? = nil) {
        self.studentNumber = studentNumber
        self.displayName = displayName
        self.portraitJPEGData = portraitJPEGData
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// Whether this value is safe to persist. Use `validate()` when the
    /// caller needs the exact reason.
    public var isValid: Bool { (try? validate()) != nil }

    public func validate() throws {
        guard Self.isValidStudentNumber(studentNumber) else {
            throw StudentIDProfileValidationError.invalidStudentNumber
        }

        if let displayName {
            guard Self.isValidDisplayName(displayName) else {
                throw StudentIDProfileValidationError.invalidDisplayName
            }
        }

        if let portraitJPEGData {
            guard Self.isJPEGData(portraitJPEGData),
                  portraitJPEGData.count <= Self.maxPortraitJPEGBytes else {
                throw StudentIDProfileValidationError.invalidPortraitJPEG
            }
        }

        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              createdAt <= updatedAt else {
            throw StudentIDProfileValidationError.invalidMetadata
        }
    }

    public static func isValidStudentNumber(_ value: String) -> Bool {
        supportedStudentNumberLengths.contains(value.utf8.count) &&
            !value.isEmpty &&
            value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    /// Returns a scanner/store-safe number after trimming surrounding input.
    /// Internal whitespace and punctuation are not removed, which preserves
    /// leading zeroes without silently changing a number the user entered.
    public static func normalizedStudentNumber(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidStudentNumber(trimmed) ? trimmed : nil
    }

    private static func isValidDisplayName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maxDisplayNameLength else { return false }
        return !trimmed.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }

    /// JPEG's SOI/EOI markers are cheap to check here. The app-side scanner
    /// performs the actual image decode before it returns a portrait.
    public static func isJPEGData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[data.startIndex] == 0xFF &&
            data[data.startIndex + 1] == 0xD8 &&
            data[data.endIndex - 2] == 0xFF &&
            data[data.endIndex - 1] == 0xD9
    }
}

public enum StudentIDProfileValidationError: Error, Equatable, Sendable {
    case invalidStudentNumber
    case invalidDisplayName
    case invalidPortraitJPEG
    case invalidMetadata
}

extension StudentIDProfileValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidStudentNumber:
            return "The student number must contain only digits and be 4–12 digits long."
        case .invalidDisplayName:
            return "The display name is empty, too long, or contains unsupported characters."
        case .invalidPortraitJPEG:
            return "The portrait must be a JPEG image within the supported size limit."
        case .invalidMetadata:
            return "The profile timestamps are invalid."
        }
    }
}
