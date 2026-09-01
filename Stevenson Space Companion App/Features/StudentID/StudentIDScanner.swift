import CoreImage
import CoreGraphics
import Foundation
import ImageIO
import ScheduleKit
import UIKit
import Vision

/// The derived values returned after a student-ID image passes both barcode
/// and independent visible-text verification. The original image is never
/// retained here.
public nonisolated struct StudentIDScanResult: Equatable, Hashable, Sendable {
    public let studentNumber: String
    /// The raw Vision symbology identifier for the matched Code 39 barcode.
    public let symbology: String
    public let suggestedName: String?
    public let portraitJPEGData: Data?

    public init(studentNumber: String,
                symbology: String,
                suggestedName: String? = nil,
                portraitJPEGData: Data? = nil) {
        self.studentNumber = studentNumber
        self.symbology = symbology
        self.suggestedName = suggestedName
        self.portraitJPEGData = portraitJPEGData
    }
}

public nonisolated enum StudentIDScannerError: Error, Equatable, Sendable {
    case invalidImage
    case unreadableBarcode
    case missingVisibleNumber
    case barcodeMismatch
    case ambiguousBarcode
}

extension StudentIDScannerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected image could not be decoded."
        case .unreadableBarcode:
            return "No readable numeric barcode was found."
        case .missingVisibleNumber:
            return "The student number is not readable in the visible text."
        case .barcodeMismatch:
            return "The visible student number does not match the barcode."
        case .ambiguousBarcode:
            return "More than one barcode or visible number matched; scan one ID at a time."
        }
    }
}

/// Performs all ID analysis on-device with Vision.
public nonisolated struct StudentIDScanner: Sendable {
    public var detectsPortrait: Bool

    public init(detectsPortrait: Bool = true) {
        self.detectsPortrait = detectsPortrait
    }

    /// Async entry point for SwiftUI tasks. Vision is synchronous, so perform
    /// the complete decode/OCR/face pass in a detached task rather than on the
    /// caller's (normally MainActor) executor.
    public func scan(imageData: Data) async throws -> StudentIDScanResult {
        let scanner = self
        return try await Task.detached(priority: .userInitiated) {
            try scanner.scanSynchronously(imageData)
        }.value
    }

    private func scanSynchronously(_ imageData: Data) throws -> StudentIDScanResult {
        let prepared: PreparedImage
        do {
            prepared = try PreparedImage(data: imageData)
        } catch {
            throw StudentIDScannerError.invalidImage
        }

        let barcodeRequest = VNDetectBarcodesRequest()
        barcodeRequest.symbologies = [.code39, .code39Checksum, .code39FullASCII]
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        textRequest.minimumTextHeight = 0.008

        do {
            try VNImageRequestHandler(cgImage: prepared.image,
                                      orientation: .up,
                                      options: [:]).perform([barcodeRequest])
        } catch {
            throw StudentIDScannerError.unreadableBarcode
        }

        do {
            try VNImageRequestHandler(cgImage: prepared.image,
                                      orientation: .up,
                                      options: [:]).perform([textRequest])
        } catch {
            throw StudentIDScannerError.missingVisibleNumber
        }

        let barcodeObservations = barcodeRequest.results ?? []
        guard !barcodeObservations.isEmpty else {
            throw StudentIDScannerError.unreadableBarcode
        }

        let candidates = barcodeObservations.compactMap {
            BarcodeCandidate(observation: $0)
        }
        guard !candidates.isEmpty else {
            throw StudentIDScannerError.unreadableBarcode
        }

        let textObservations = textRequest.results ?? []
        let textLines = textObservations.compactMap {
            OCRLine(observation: $0)
        }
        let visibleNumbers = Set(textLines.flatMap {
            Self.numberCandidates(in: $0.text)
        })
        guard !visibleNumbers.isEmpty else {
            throw StudentIDScannerError.missingVisibleNumber
        }

        let barcodeNumbers = Set(candidates.map(\.number))
        let matchingNumbers = barcodeNumbers.intersection(visibleNumbers)
        guard !matchingNumbers.isEmpty else {
            if barcodeNumbers.count > 1 {
                throw StudentIDScannerError.ambiguousBarcode
            }
            throw StudentIDScannerError.barcodeMismatch
        }
        guard matchingNumbers.count == 1 else {
            throw StudentIDScannerError.ambiguousBarcode
        }

        let number = matchingNumbers.first!
        // A duplicate decode of the same payload is not ambiguous. Vision's
        // confidence ordering makes the returned symbology deterministic.
        guard let winningBarcode = candidates
            .filter({ $0.number == number })
            .sorted(by: BarcodeCandidate.preferred)
            .first else {
            throw StudentIDScannerError.barcodeMismatch
        }

        let name = Self.suggestedName(from: textLines,
                                      studentNumber: number)
        let portrait = detectsPortrait
            ? Self.portraitJPEG(from: prepared.image)
            : nil

        return StudentIDScanResult(studentNumber: number,
                                   symbology: winningBarcode.symbology,
                                   suggestedName: name,
                                   portraitJPEGData: portrait)
    }

    // MARK: - Vision value extraction

    private struct PreparedImage {
        let image: CGImage

        init(data: Data) throws {
            guard !data.isEmpty,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  sourceImage.width > 0,
                  sourceImage.height > 0 else {
                throw StudentIDScannerError.invalidImage
            }

            let orientation = Self.orientation(from: source)
            // Vision observations use normalized coordinates in the oriented
            // image. Normalize once so OCR, face bounds, and the eventual crop
            // all share the same top-level coordinate system.
            let ciImage = CIImage(cgImage: sourceImage)
                .oriented(forExifOrientation: Int32(orientation.rawValue))
            let context = CIContext(options: nil)
            guard let normalized = context.createCGImage(ciImage,
                                                          from: ciImage.extent),
                  normalized.width > 0,
                  normalized.height > 0 else {
                throw StudentIDScannerError.invalidImage
            }
            image = normalized
        }

        private static func orientation(from source: CGImageSource) -> CGImagePropertyOrientation {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [String: Any],
                  let raw = (properties[kCGImagePropertyOrientation as String]
                              as? NSNumber)?.uint32Value,
                  let orientation = CGImagePropertyOrientation(rawValue: raw) else {
                return .up
            }
            return orientation
        }
    }

    private struct BarcodeCandidate {
        let number: String
        let symbology: String
        let confidence: Float
        let bounds: CGRect

        init?(observation: VNBarcodeObservation) {
            guard let payload = observation.payloadStringValue,
                  let number = StudentIDProfile.normalizedStudentNumber(payload) else {
                return nil
            }
            self.number = number
            self.symbology = observation.symbology.rawValue
            self.confidence = observation.confidence
            self.bounds = observation.boundingBox
        }

        static func preferred(_ lhs: BarcodeCandidate,
                              _ rhs: BarcodeCandidate) -> Bool {
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            if lhs.symbology != rhs.symbology {
                return lhs.symbology < rhs.symbology
            }
            return lhs.bounds.origin.y > rhs.bounds.origin.y
        }
    }

    private struct OCRLine {
        let text: String
        let confidence: Float
        let bounds: CGRect

        init?(observation: VNRecognizedTextObservation) {
            guard let recognized = observation.topCandidates(1).first else {
                return nil
            }
            let value = recognized.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            text = value
            confidence = recognized.confidence
            bounds = observation.boundingBox
        }

    }

    /// Extracts complete ASCII digit runs, plus runs split only by common
    /// number separators (spaces, hyphens, en/em dashes, and periods). This
    /// intentionally leaves leading zeroes untouched and does not reinterpret
    /// letters such as `O` as zero. A label or another alphanumeric token
    /// always ends the candidate.
    private static func numberCandidates(in text: String) -> [String] {
        var runs: [String] = []
        var current = ""

        func flush() {
            guard !current.isEmpty else { return }
            if StudentIDProfile.isValidStudentNumber(current) {
                runs.append(current)
            }
            current.removeAll(keepingCapacity: true)
        }

        for scalar in text.unicodeScalars {
            if scalar.value >= 48 && scalar.value <= 57 {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty && Self.isNumberSeparator(scalar) {
                // Keep the separator out of the value while allowing OCR such
                // as `0000-1234` or `0000 1234` to normalize to one number.
                continue
            } else {
                flush()
            }
        }
        flush()
        return runs
    }

    private static func isNumberSeparator(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x20, 0x2D, 0x2E, 0x2013, 0x2014:
            return true
        default:
            return false
        }
    }

    // MARK: - Name suggestion

    private struct NameCandidate {
        let name: String
        let score: Double
    }

    private static let nameStopWords: Set<String> = [
        "account", "address", "campus", "card", "class", "date", "dob",
        "email", "expires", "grade", "high", "id", "identification",
        "infinite", "information", "login", "name", "number", "photo",
        "portal", "profile", "school", "student", "status", "stevenson",
        "year"
    ]

    private static func suggestedName(from lines: [OCRLine],
                                      studentNumber: String) -> String? {
        guard !lines.isEmpty else { return nil }

        // Vision's normalized origin is bottom-left, so descending y gives a
        // natural reading order for label/value pairs on both card layouts.
        let ordered = lines.sorted {
            if abs($0.bounds.midY - $1.bounds.midY) > 0.025 {
                return $0.bounds.midY > $1.bounds.midY
            }
            return $0.bounds.minX < $1.bounds.minX
        }

        let numberLineIndices = Set(ordered.indices.filter {
            numberCandidates(in: ordered[$0].text).contains(studentNumber)
        })
        var candidates: [NameCandidate] = []

        for index in ordered.indices {
            let line = ordered[index]
            let hasDigits = line.text.unicodeScalars.contains {
                $0.value >= 48 && $0.value <= 57
            }

            // Explicit labels are high-confidence in Infinite Campus and on
            // the physical card. Values may be inline (`Name: A B`) or on the
            // following OCR line (`Student Name` then `A B`).
            if let remainder = Self.nameLabelRemainder(line.text),
               let name = Self.canonicalName(remainder) {
                candidates.append(NameCandidate(name: name,
                                                score: 120 + Double(line.confidence) * 10))
                continue
            }

            if Self.isStandaloneNameLabel(line.text),
               let next = Self.nextNameLine(after: index, in: ordered),
               let name = Self.canonicalName(next.text) {
                let distance = abs(line.bounds.midY - next.bounds.midY)
                candidates.append(NameCandidate(
                    name: name,
                    score: 112 + Double(next.confidence) * 10 - distance * 20))
                continue
            }

            // Anything containing digits is an ID/grade/date candidate rather
            // than a person name. This also rules out the verified number even
            // when OCR returned it in a longer line.
            guard !hasDigits,
                  !numberLineIndices.contains(index),
                  let name = Self.canonicalName(line.text) else { continue }

            var score = 35 + Double(line.confidence) * 12
            if line.text.contains(",") { score += 12 }
            if line.text == line.text.uppercased() { score += 5 }

            // A name next to the student-number field is more likely than a
            // distant page heading, without making geometry a hard rule for a
            // rotated physical card.
            if let numberIndex = numberLineIndices.min(by: {
                abs(ordered[$0].bounds.midY - line.bounds.midY) <
                    abs(ordered[$1].bounds.midY - line.bounds.midY)
            }) {
                let distance = abs(ordered[numberIndex].bounds.midY - line.bounds.midY)
                score += max(0, 16 - distance * 16)
            }
            candidates.append(NameCandidate(name: name, score: score))
        }

        return candidates.max {
            if abs($0.score - $1.score) > 0.001 { return $0.score < $1.score }
            return $0.name > $1.name
        }?.name
    }

    private static func nameLabelRemainder(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        let labels = ["preferred name", "student name", "full name", "name", "student"]
        guard let label = labels.first(where: {
            lower == $0 || lower.hasPrefix($0 + ":") ||
                lower.hasPrefix($0 + "-") || lower.hasPrefix($0 + " ")
        }) else { return nil }

        value.removeFirst(label.count)
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = value.first, ":-#|".contains(first) {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.isEmpty ? nil : value
    }

    private static func isStandaloneNameLabel(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalized = lower.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        return normalized == "name" || normalized == "student name" ||
            normalized == "full name" || normalized == "preferred name" ||
            normalized == "student"
    }

    private static func nextNameLine(after index: Int,
                                     in lines: [OCRLine]) -> OCRLine? {
        guard index + 1 < lines.count else { return nil }
        let next = lines[index + 1]
        let verticalDistance = abs(lines[index].bounds.midY - next.bounds.midY)
        return verticalDistance <= 0.22 ? next : nil
    }

    private static func canonicalName(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let remainder = nameLabelRemainder(value) {
            value = remainder
        }

        // Physical IDs commonly print `LAST, FIRST`; return a natural editable
        // suggestion while preserving all actual name tokens.
        let commaParts = value.split(separator: ",", maxSplits: 1,
                                     omittingEmptySubsequences: true)
        let sourceTokens: [Substring]
        if commaParts.count == 2 {
            sourceTokens = commaParts[1].split(whereSeparator: { $0.isWhitespace }) +
                commaParts[0].split(whereSeparator: { $0.isWhitespace })
        } else {
            sourceTokens = value.split(whereSeparator: { $0.isWhitespace })
        }

        var tokens: [String] = []
        for source in sourceTokens {
            let token = source.trimmingCharacters(in: CharacterSet.punctuationCharacters)
            guard !token.isEmpty,
                  token.count >= 2,
                  token.unicodeScalars.allSatisfy({
                      CharacterSet.letters.contains($0) || $0.value == 0x27 ||
                          $0.value == 0x2D
                  }) else { return nil }
            let lowered = token.lowercased()
            guard !nameStopWords.contains(lowered) else { return nil }
            tokens.append(token)
        }

        guard (2...4).contains(tokens.count) else { return nil }
        return tokens.map(Self.userFacingNameToken).joined(separator: " ")
    }

    private static func userFacingNameToken(_ token: String) -> String {
        guard token == token.uppercased() else { return token }

        // Preserve apostrophes and hyphens when converting common all-caps OCR
        // output into a readable suggestion (`O'NEIL` → `O'Neil`).
        return token.lowercased().split(separator: "-", omittingEmptySubsequences: false)
            .map { piece in
                piece.split(separator: "'", omittingEmptySubsequences: false)
                    .map { part in
                        guard let first = part.first else { return "" }
                        return String(first).uppercased() + part.dropFirst()
                    }
                    .joined(separator: "'")
            }
            .joined(separator: "-")
    }

    // MARK: - Optional portrait

    private static func portraitJPEG(from image: CGImage) -> Data? {
        let request = VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(cgImage: image,
                                      orientation: .up,
                                      options: [:]).perform([request])
        } catch {
            return nil
        }

        guard let face = request.results?
            .max(by: { $0.boundingBox.width * $0.boundingBox.height <
                       $1.boundingBox.width * $1.boundingBox.height }) else {
            return nil
        }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let normalizedRect = VNImageRectForNormalizedRect(face.boundingBox,
                                                          Int(width),
                                                          Int(height))
        // Vision's normalized origin is bottom-left; CGImage cropping uses a
        // top-left-oriented pixel rectangle.
        let pixelRect = CGRect(x: normalizedRect.minX,
                               y: height - normalizedRect.maxY,
                               width: normalizedRect.width,
                               height: normalizedRect.height)
        let expanded = pixelRect.insetBy(dx: -pixelRect.width * 0.75,
                                         dy: -pixelRect.height * 1.0)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let cropRect = expanded.intersection(bounds).integral
        guard cropRect.width >= 8,
              cropRect.height >= 8,
              let cropped = image.cropping(to: cropRect) else {
            return nil
        }

        let source = UIImage(cgImage: cropped,
                             scale: 1,
                             orientation: .up)
        let maxDimension: CGFloat = 640
        let sourceSize = source.size
        let scale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let output: UIImage
        if scale < 1 {
            let size = CGSize(width: sourceSize.width * scale,
                              height: sourceSize.height * scale)
            output = UIGraphicsImageRenderer(size: size).image { _ in
                source.draw(in: CGRect(origin: .zero, size: size))
            }
        } else {
            output = source
        }
        return output.jpegData(compressionQuality: 0.84)
    }
}
