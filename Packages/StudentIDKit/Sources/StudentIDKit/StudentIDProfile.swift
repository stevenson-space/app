import Foundation

public struct StudentIDProfile: Codable, Equatable, Sendable {
    public let studentName: String
    public let studentNumber: String

    public init(studentName: String, studentNumber: String) {
        self.studentName = Self.normalizeName(studentName)
        self.studentNumber = Code39Encoder.normalizedPayload(studentNumber)
    }

    public var validationMessage: String? {
        if studentName.isEmpty {
            return "Enter the student’s name."
        }
        if studentName.count > 80 {
            return "The student name is too long."
        }
        if studentNumber.count > 12 {
            return "The student number is too long to display reliably."
        }
        do {
            _ = try Code39Encoder.encode(studentNumber)
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "Enter a valid student number."
        }
        return nil
    }

    public var isValid: Bool { validationMessage == nil }

    private static func normalizeName(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
