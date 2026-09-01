import Foundation

public struct Code39Run: Equatable, Sendable {
    public let isBar: Bool
    public let modules: Int

    public init(isBar: Bool, modules: Int) {
        self.isBar = isBar
        self.modules = modules
    }
}

public struct Code39Symbol: Equatable, Sendable {
    public let payload: String
    public let runs: [Code39Run]
    public let totalModules: Int

    public init(payload: String, runs: [Code39Run]) {
        self.payload = payload
        self.runs = runs
        self.totalModules = runs.reduce(0) { $0 + $1.modules }
    }

    /// The narrowest screen width that keeps every narrow module at a whole,
    /// scanner-friendly physical-pixel width.
    public func minimumWidthPoints(displayScale: CGFloat, narrowModulePixels: Int = 4) -> CGFloat {
        guard displayScale > 0 else { return .infinity }
        return CGFloat(totalModules * narrowModulePixels) / displayScale
    }
}

public enum Code39Error: Error, Equatable, LocalizedError {
    case emptyPayload
    case unsupportedCharacter(Character)

    public var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "Enter a student number."
        case .unsupportedCharacter(let character):
            return "“\(character)” cannot be encoded as Code 39."
        }
    }
}

public enum Code39Encoder {
    /// Standard Code 39 patterns. Each character has five bars and four spaces;
    /// `w` is three times the width of `n`.
    private static let patterns: [Character: String] = [
        "0": "nnnwwnwnn", "1": "wnnwnnnnw", "2": "nnwwnnnnw",
        "3": "wnwwnnnnn", "4": "nnnwwnnnw", "5": "wnnwwnnnn",
        "6": "nnwwwnnnn", "7": "nnnwnnwnw", "8": "wnnwnnwnn",
        "9": "nnwwnnwnn", "A": "wnnnnwnnw", "B": "nnwnnwnnw",
        "C": "wnwnnwnnn", "D": "nnnnwwnnw", "E": "wnnnwwnnn",
        "F": "nnwnwwnnn", "G": "nnnnnwwnw", "H": "wnnnnwwnn",
        "I": "nnwnnwwnn", "J": "nnnnwwwnn", "K": "wnnnnnnww",
        "L": "nnwnnnnww", "M": "wnwnnnnwn", "N": "nnnnwnnww",
        "O": "wnnnwnnwn", "P": "nnwnwnnwn", "Q": "nnnnnnwww",
        "R": "wnnnnnwwn", "S": "nnwnnnwwn", "T": "nnnnwnwwn",
        "U": "wwnnnnnnw", "V": "nwwnnnnnw", "W": "wwwnnnnnn",
        "X": "nwnnwnnnw", "Y": "wwnnwnnnn", "Z": "nwwnwnnnn",
        "-": "nwnnnnwnw", ".": "wwnnnnwnn", " ": "nwwnnnwnn",
        "$": "nwnwnwnnn", "/": "nwnwnnnwn", "+": "nwnnnwnwn",
        "%": "nnnwnwnwn", "*": "nwnnwnwnn",
    ]

    public static var supportedPayloadCharacters: Set<Character> {
        Set(patterns.keys).subtracting(["*"])
    }

    public static func normalizedPayload(_ payload: String) -> String {
        payload.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func encode(_ rawPayload: String) throws -> Code39Symbol {
        let payload = normalizedPayload(rawPayload)
        guard !payload.isEmpty else { throw Code39Error.emptyPayload }

        for character in payload where patterns[character] == nil || character == "*" {
            throw Code39Error.unsupportedCharacter(character)
        }

        let characters = Array("*\(payload)*")
        var runs: [Code39Run] = [Code39Run(isBar: false, modules: 10)]

        for (characterIndex, character) in characters.enumerated() {
            guard let pattern = patterns[character] else { continue }
            for (elementIndex, width) in pattern.enumerated() {
                append(
                    Code39Run(isBar: elementIndex.isMultiple(of: 2),
                              modules: width == "w" ? 3 : 1),
                    to: &runs
                )
            }
            if characterIndex < characters.count - 1 {
                append(Code39Run(isBar: false, modules: 1), to: &runs)
            }
        }

        append(Code39Run(isBar: false, modules: 10), to: &runs)
        return Code39Symbol(payload: payload, runs: runs)
    }

    private static func append(_ run: Code39Run, to runs: inout [Code39Run]) {
        guard let last = runs.last, last.isBar == run.isBar else {
            runs.append(run)
            return
        }
        runs[runs.count - 1] = Code39Run(isBar: last.isBar,
                                         modules: last.modules + run.modules)
    }
}
