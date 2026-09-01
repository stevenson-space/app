import Foundation
import Vision

public struct StudentIDAnalysis: Equatable, Sendable {
    public let barcodeValue: String?
    public let suggestedName: String?

    public init(barcodeValue: String?, suggestedName: String?) {
        self.barcodeValue = barcodeValue
        self.suggestedName = suggestedName
    }
}

public enum StudentIDAnalysisError: Error, LocalizedError {
    case unreadableImage

    public var errorDescription: String? {
        "The selected image could not be read. Choose the original ID screenshot and try again."
    }
}

public enum StudentIDAnalyzer {
    public static func analyze(_ imageData: Data) async throws -> StudentIDAnalysis {
        guard !imageData.isEmpty else { throw StudentIDAnalysisError.unreadableImage }
        return try await Task.detached(priority: .userInitiated) {
            try analyzeSynchronously(imageData)
        }.value
    }

    private static func analyzeSynchronously(_ imageData: Data) throws -> StudentIDAnalysis {
        let barcodeRequest = VNDetectBarcodesRequest()
        barcodeRequest.symbologies = [
            .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum,
        ]

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        textRequest.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        do {
            try handler.perform([barcodeRequest, textRequest])
        } catch {
            throw StudentIDAnalysisError.unreadableImage
        }

        let barcodeObservation = barcodeRequest.results?
            .filter { $0.payloadStringValue != nil }
            .max { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.boundingBox.width * lhs.boundingBox.height
                        < rhs.boundingBox.width * rhs.boundingBox.height
                }
                return lhs.confidence < rhs.confidence
            }

        let barcode = barcodeObservation?.payloadStringValue.map {
            Code39Encoder.normalizedPayload(
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            )
        }
        let name = suggestedName(
            from: textRequest.results ?? [],
            barcodeBounds: barcodeObservation?.boundingBox
        )
        return StudentIDAnalysis(barcodeValue: barcode, suggestedName: name)
    }

    private static func suggestedName(
        from observations: [VNRecognizedTextObservation],
        barcodeBounds: CGRect?
    ) -> String? {
        let excludedFragments = [
            "student profile", "items in cart", "enrollments", "student number",
            "student identification", "barcode", "adlai e stevenson", "grade ",
            "ended", "today's schedule", "term sem", "teacher", "room", "day: periods",
        ]

        struct Candidate {
            let value: String
            let score: Float
        }

        let candidates: [Candidate] = observations.compactMap { observation in
            guard let recognized = observation.topCandidates(1).first else { return nil }
            let value = recognized.string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            let lowercased = value.lowercased()
            let words = value.split(separator: " ")
            let letters = value.filter(\.isLetter)

            guard words.count >= 2, words.count <= 5, letters.count >= 4 else { return nil }
            guard !excludedFragments.contains(where: lowercased.contains) else { return nil }
            if let barcodeBounds, observation.boundingBox.minY <= barcodeBounds.maxY {
                return nil
            }

            let uppercaseCount = letters.filter(\.isUppercase).count
            let looksAllCaps = uppercaseCount > max(2, letters.count * 2 / 3)
            let verticalPreference = Float(observation.boundingBox.midY)
            let score = recognized.confidence * 4
                + Float(observation.boundingBox.height) * 8
                + verticalPreference
                - (looksAllCaps ? 1 : 0)
            return Candidate(value: value, score: score)
        }

        return candidates.max { $0.score < $1.score }?.value
    }
}
