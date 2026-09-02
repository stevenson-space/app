import CoreGraphics
import Foundation

/// One line of recognized text, positioned in image coordinates with the origin
/// at the top left — the way the page reads, rather than Vision's bottom-left
/// convention.
struct TextLine: Equatable, Sendable {
    let text: String
    let frame: CGRect

    /// Lowercased, whitespace-collapsed, punctuation-normalized: what the
    /// anchor matching compares against.
    let normalized: String

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " :.,"))
    }

    init(text: String, frame: CGRect) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.frame = frame
        normalized = Self.normalize(self.text)
    }
}

/// Pulls the fields out of a recognized Infinite Campus Student Profile page.
///
/// Deliberately pure — it takes recognized lines, not an image — so every
/// heuristic here is unit-testable without running OCR, and OCR only has to be
/// exercised once end to end.
///
/// The page reads, top to bottom: the student's name; a bold "Enrollments"
/// label; one or more `<year> <school>` / `Grade <n>` pairs, a finished one
/// carrying an "ENDED" badge; a "Student Number" label above the number; and a
/// "Student Identification Barcode" section. The name is located relative to the
/// "Enrollments" label rather than by absolute position, so it survives a
/// different device size, Dynamic Type, or an extra enrollment row.
enum ProfileTextParser {

    // MARK: Anchors

    static func line(matching phrase: String, in lines: [TextLine]) -> TextLine? {
        lines.first { $0.normalized == phrase } ?? lines.first { $0.normalized.contains(phrase) }
    }

    /// Guards against importing some unrelated Code 39 barcode as a student ID.
    static func looksLikeProfilePage(_ lines: [TextLine]) -> Bool {
        let anchors = ["enrollments", "student number", "student identification barcode", "student profile"]
        // Two independent labels, not one: a single stray phrase is the kind of
        // thing an unrelated page can carry by accident.
        let matched = anchors.filter { phrase in lines.contains { $0.normalized.contains(phrase) } }
        return matched.count >= 2
    }

    // MARK: Student number

    static func printedStudentNumber(in lines: [TextLine], matching barcodePayloads: [String] = []) -> String? {
        guard let anchor = line(matching: "student number", in: lines) else { return nil }

        func number(in text: String) -> String? {
            let numbers = digitPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { capture(0, of: $0, in: text) }
                .filter(StudentIDCard.isValidNumber)
            // OCR can merge a year with the number. Use the barcode to choose
            // among plausible values on this line; four-digit IDs remain valid.
            return numbers.first(where: barcodePayloads.contains) ?? numbers.first
        }

        // Recognition sometimes merges the label and its value into one line.
        if let inline = number(in: anchor.text) {
            return inline
        }

        let below = lines
            .filter { $0.frame.minY >= anchor.frame.minY + anchor.frame.height * 0.5 }
            .filter { horizontallyOverlaps($0.frame, anchor.frame) }
            .sorted { $0.frame.minY < $1.frame.minY }

        for candidate in below {
            if let digits = number(in: candidate.text) { return digits }
        }
        return nil
    }

    // MARK: Name

    static func fullName(in lines: [TextLine], imageHeight: CGFloat) -> String? {
        if let anchor = line(matching: "enrollments", in: lines) {
            let above = lines
                .filter { $0.frame.maxY <= anchor.frame.minY + anchor.frame.height * 0.5 }
                .filter { horizontallyOverlaps($0.frame, anchor.frame, minimum: 0) }
                .sorted { $0.frame.maxY > $1.frame.maxY }
            for candidate in above {
                let joined = joinedAcrossBaseline(candidate, in: lines)
                if looksLikePersonName(joined) { return joined }
            }
        }

        // No anchor: the name is the largest text on the upper part of the page.
        let tallestFirst = lines
            .filter { $0.frame.midY < imageHeight * 0.45 }
            .sorted { $0.frame.height > $1.frame.height }
        for candidate in tallestFirst {
            let joined = joinedAcrossBaseline(candidate, in: lines)
            if looksLikePersonName(joined) { return joined }
        }
        return nil
    }

    /// Recognition occasionally splits a wide name into two observations on the
    /// same baseline. Stitch those back together, left to right.
    static func joinedAcrossBaseline(_ line: TextLine, in lines: [TextLine]) -> String {
        let sameBaseline = lines.filter { other in
            abs(other.frame.midY - line.frame.midY) < line.frame.height * 0.6
                && isNameShaped(other.text)
        }
        guard sameBaseline.count > 1 else { return line.text }

        // Recognition order says nothing about position, so walk out from the
        // line itself in both directions and stop at the first gap wide enough
        // to be a different column rather than the next word.
        let ordered = sameBaseline.sorted { $0.frame.minX < $1.frame.minX }
        guard let anchor = ordered.firstIndex(of: line) else { return line.text }
        let widestGap = line.frame.height * 1.5

        var first = anchor
        while first > 0, ordered[first].frame.minX - ordered[first - 1].frame.maxX <= widestGap {
            first -= 1
        }
        var last = anchor
        while last + 1 < ordered.count,
              ordered[last + 1].frame.minX - ordered[last].frame.maxX <= widestGap {
            last += 1
        }
        return ordered[first...last].map(\.text).joined(separator: " ")
    }

    /// Recognizable page labels and school names. Single words such as Summer
    /// or Stevenson can be part of a student's name.
    private static let stopPhrases = [
        "student profile", "student number", "student identification",
        "today's schedule", "items in cart", "high school", "adlai e stevenson",
        "stevenson high", "stevenson summer", "summer school", "day periods",
    ]
    private static let stopWords: Set<String> = [
        "ended", "grade", "day", "periods", "cart", "wallet", "sem", "settings",
        "summer", "enrollment", "enrollments", "teacher", "room", "term",
    ]

    static func looksLikePersonName(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNameShaped(trimmed) else { return false }
        guard (2...60).contains(trimmed.count) else { return false }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard (1...5).contains(words.count) else { return false }
        guard trimmed.filter(\.isLetter).count >= 2 else { return false }

        let normalized = TextLine.normalize(trimmed)
        if stopWords.contains(normalized) { return false }
        let phrase = " " + normalized.split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .joined(separator: " ") + " "
        if stopPhrases.contains(where: { phrase.contains(" " + $0 + " ") }) { return false }
        return true
    }

    /// Letters and the punctuation real names carry — nothing else. This is what
    /// keeps prices, dates, and ID numbers out of the name slot.
    private static func isNameShaped(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy { character in
            character.isLetter || character.isWhitespace
                || character == "'" || character == "\u{2019}"
                || character == "-" || character == "." || character == ","
        }
    }

    // MARK: Grade and school year

    static func gradeLevel(in lines: [TextLine]) -> Int? {
        let ordered = lines.sorted(by: readingOrder)
        let endedBadges = ordered.filter { $0.normalized == "ended" }

        /// A grade sitting just above an ENDED badge belongs to a finished
        /// enrollment (the summer session), not the one the student is in now.
        func belongsToEndedEnrollment(_ line: TextLine) -> Bool {
            endedBadges.contains { badge in
                badge.frame.minY > line.frame.minY
                    && badge.frame.minY - line.frame.maxY < line.frame.height * 2.5
            }
        }

        var fallback: Int?
        for line in ordered {
            guard let grade = firstGrade(in: line.text) else { continue }
            if fallback == nil { fallback = grade }
            if belongsToEndedEnrollment(line) { continue }
            return grade
        }
        return fallback
    }

    static func schoolYearStart(in lines: [TextLine]) -> Int? {
        for line in lines.sorted(by: readingOrder) {
            for match in yearPattern.matches(in: line.text, range: NSRange(line.text.startIndex..., in: line.text)) {
                guard let first = Int(capture(1, of: match, in: line.text) ?? ""),
                      let second = Int(capture(2, of: match, in: line.text) ?? ""),
                      (first + 1) % 100 == second else { continue }
                return 2000 + first
            }
        }
        return nil
    }

    // MARK: Geometry helpers

    static func readingOrder(_ lhs: TextLine, _ rhs: TextLine) -> Bool {
        (lhs.frame.minY, lhs.frame.minX) < (rhs.frame.minY, rhs.frame.minX)
    }

    private static func horizontallyOverlaps(_ lhs: CGRect, _ rhs: CGRect, minimum: CGFloat = 0) -> Bool {
        let overlap = min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX)
        if overlap > minimum { return true }
        // Left-aligned in the same column counts even when one line is short.
        return abs(lhs.minX - rhs.minX) < max(lhs.height, rhs.height) * 2
    }

    // MARK: Patterns

    private static let gradePattern = try! NSRegularExpression(
        pattern: "\\bgrade\\s+([0-9]{1,2})\\b", options: [.caseInsensitive])
    private static let yearPattern = try! NSRegularExpression(
        pattern: "\\b([0-9]{2})\\s*[-\\x{2013}\\x{2014}/]\\s*([0-9]{2})\\b")
    /// Boundaries on both sides: a longer run of digits is somebody else's
    /// number, not a student number with its tail cut off.
    private static let digitPattern = try! NSRegularExpression(
        pattern: "(?<![0-9])[0-9]{3,10}(?![0-9])")

    private static func firstGrade(in text: String) -> Int? {
        guard let match = firstMatch(gradePattern, in: text),
              let grade = Int(capture(1, of: match, in: text) ?? ""),
              (1...12).contains(grade) else { return nil }
        return grade
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func capture(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}
