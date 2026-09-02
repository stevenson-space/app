import Foundation

/// A student ID, as read off an Infinite Campus screenshot.
///
/// The memberwise initializer is deliberately **internal**: the only way the app
/// can obtain a card is `StudentIDExtractor.extract(from:)`. Nothing in the UI can
/// mint one, which is what makes "students cannot type their own name or number"
/// a structural guarantee rather than a promise about button placement.
public struct StudentIDCard: Equatable, Sendable {
    /// The number a scanner reads. Always digits.
    public let idNumber: String
    /// The exact payload to re-encode, so the recreation is the same symbol the
    /// school issued rather than a lookalike.
    public let barcodePayload: String
    /// True when the source symbol carried a modulo-43 check character.
    public let requiresCheckDigit: Bool
    public let fullName: String?
    public let gradeLevel: Int?
    /// Calendar year the school year began: 2026 for "26-27".
    public let schoolYearStart: Int?
    public let importedAt: Date

    /// Student numbers seen in the wild are five digits; the range is generous
    /// enough to survive the school changing its numbering without accepting an
    /// arbitrary barcode.
    static let numberLengthRange = 4...8

    init(idNumber: String,
         barcodePayload: String,
         requiresCheckDigit: Bool,
         fullName: String?,
         gradeLevel: Int?,
         schoolYearStart: Int?,
         importedAt: Date) {
        self.idNumber = idNumber
        self.barcodePayload = barcodePayload
        self.requiresCheckDigit = requiresCheckDigit
        self.fullName = fullName
        self.gradeLevel = gradeLevel
        self.schoolYearStart = schoolYearStart
        self.importedAt = importedAt
    }

    static func isValidNumber(_ value: String) -> Bool {
        !value.isEmpty
            && numberLengthRange.contains(value.count)
            // ASCII digits only: Code 39 cannot encode an Arabic-Indic five,
            // and a scanner would never read one back.
            && value.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// "26–27", using an en dash, as the physical card prints it.
    public var schoolYearLabel: String? {
        guard let start = schoolYearStart else { return nil }
        let end = (start + 1) % 100
        return String(format: "%02d\u{2013}%02d", start % 100, end)
    }

    public var gradeLabel: String? {
        gradeLevel.map { "Grade \($0)" }
    }

    // MARK: - Storage

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Returns nil for anything that is not a well-formed, plausible card —
    /// including a hand-edited preferences file, which is the other way someone
    /// might try to put a number the school never issued onto the screen.
    public static func decoded(from data: Data) -> StudentIDCard? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StudentIDCard.self, from: data)
    }
}

/// Tolerant decoding, matching the rest of the app's persisted models: unknown or
/// missing optional fields never fail a load, but the identity fields are
/// validated because a card that cannot be trusted should not be shown at all.
extension StudentIDCard: Codable {
    private enum CodingKeys: String, CodingKey {
        case idNumber, barcodePayload, requiresCheckDigit
        case fullName, gradeLevel, schoolYearStart, importedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let number = try container.decode(String.self, forKey: .idNumber)
        guard StudentIDCard.isValidNumber(number) else {
            throw DecodingError.dataCorruptedError(
                forKey: .idNumber, in: container,
                debugDescription: "\"\(number)\" is not a student number")
        }
        idNumber = number

        let payload = try container.decodeIfPresent(String.self, forKey: .barcodePayload) ?? number
        guard StudentIDCard.isValidNumber(payload) else {
            throw DecodingError.dataCorruptedError(
                forKey: .barcodePayload, in: container,
                debugDescription: "\"\(payload)\" is not encodable as a student barcode")
        }
        barcodePayload = payload

        requiresCheckDigit = try container.decodeIfPresent(Bool.self, forKey: .requiresCheckDigit) ?? false
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        gradeLevel = try container.decodeIfPresent(Int.self, forKey: .gradeLevel).flatMap {
            (1...12).contains($0) ? $0 : nil
        }
        schoolYearStart = try container.decodeIfPresent(Int.self, forKey: .schoolYearStart).flatMap {
            (2000...2099).contains($0) ? $0 : nil
        }
        importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
    }
}

/// Things worth telling the student about an import that still succeeded.
public enum StudentIDWarning: String, Equatable, Sendable, CaseIterable, Codable {
    case nameNotFound
    case photoNotFound
    case gradeNotFound
    case schoolYearNotFound
    case printedNumberNotFound
}

/// Everything one screenshot yielded.
public struct StudentIDExtraction: Sendable {
    public let card: StudentIDCard
    /// A cropped headshot, JPEG encoded. Nil when no face was found.
    public let photoJPEG: Data?
    public let warnings: [StudentIDWarning]
}

public enum StudentIDImportError: Error, Equatable, CustomStringConvertible {
    case unreadableImage
    case barcodeNotFound
    case unsupportedBarcodePayload(String)
    case numberMismatch(barcode: String, printed: String)
    case notAStudentProfile

    public var description: String {
        switch self {
        case .unreadableImage:
            return "That file could not be opened as an image."
        case .barcodeNotFound:
            return "No barcode found. Screenshot the whole Student Profile page, including the barcode near the bottom."
        case .unsupportedBarcodePayload:
            return "The barcode in that screenshot is not a student number."
        case .numberMismatch:
            return "The barcode and the printed student number do not match. Take a fresh screenshot."
        case .notAStudentProfile:
            return "That does not look like the Infinite Campus Student Profile page."
        }
    }
}
