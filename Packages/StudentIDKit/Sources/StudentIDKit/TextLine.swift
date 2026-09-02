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
    var normalized: String {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " :.,"))
    }

    init(text: String, frame: CGRect) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.frame = frame
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
        return anchors.contains { phrase in lines.contains { $0.normalized.contains(phrase) } }
    }

    // MARK: Student number

    static func printedStudentNumber(in lines: [TextLine]) -> String? {
        guard let anchor = line(matching: "student number", in: lines) else { return nil }

        // Recognition sometimes merges the label and its value into one line.
        if let inline = digitRun(in: anchor.text), StudentIDCard.isValidNumber(inline) {
            return inline
        }

        let below = lines
            .filter { $0.frame.minY >= anchor.frame.minY + anchor.frame.height * 0.5 }
            .filter { horizontallyOverlaps($0.frame, anchor.frame) }
            .sorted { $0.frame.minY < $1.frame.minY }

        for candidate in below {
            guard let digits = digitRun(in: candidate.text) else { continue }
            if StudentIDCard.isValidNumber(digits) { return digits }
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
                && other.frame.minX >= line.frame.minX - 0.5
                && isNameShaped(other.text)
        }
        guard sameBaseline.count > 1 else { return line.text }

        let ordered = sameBaseline.sorted { $0.frame.minX < $1.frame.minX }
        var pieces: [String] = []
        var previous: TextLine?
        for piece in ordered {
            if let previous, piece.frame.minX - previous.frame.maxX > line.frame.height * 1.5 {
                break
            }
            pieces.append(piece.text)
            previous = piece
        }
        return pieces.joined(separator: " ")
    }

    /// Words that appear on this page as labels, chrome, or school names — never
    /// as somebody's name.
    private static let stopPhrases = [
        "student profile", "student number", "student identification",
        "today's schedule", "items in cart", "high school", "adlai", "stevenson",
        "summer", "enrollment", "day: periods", "teacher", "room", "term",
    ]
    private static let stopWords: Set<String> = [
        "ended", "grade", "day", "periods", "cart", "wallet", "sem", "settings",
    ]

    static func looksLikePersonName(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNameShaped(trimmed) else { return false }
        guard (2...60).contains(trimmed.count) else { return false }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard (1...5).contains(words.count) else { return false }
        guard trimmed.filter(\.isLetter).count >= 2 else { return false }

        let normalized = TextLine(text: trimmed, frame: .zero).normalized
        if stopWords.contains(normalized) { return false }
        if stopPhrases.contains(where: { normalized.contains($0) }) { return false }
        if words.contains(where: { stopWords.contains(String($0).lowercased()) }) { return false }
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
            guard let (first, second) = firstYearPair(in: line.text) else { continue }
            guard (first + 1) % 100 == second else { continue }
            return 2000 + first
        }
        return nil
    }

    // MARK: Geometry helpers

    static func readingOrder(_ lhs: TextLine, _ rhs: TextLine) -> Bool {
        if abs(lhs.frame.minY - rhs.frame.minY) > max(lhs.frame.height, rhs.frame.height) * 0.5 {
            return lhs.frame.minY < rhs.frame.minY
        }
        return lhs.frame.minX < rhs.frame.minX
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
    private static let digitPattern = try! NSRegularExpression(pattern: "[0-9]{3,10}")

    private static func firstGrade(in text: String) -> Int? {
        guard let match = firstMatch(gradePattern, in: text),
              let grade = Int(capture(1, of: match, in: text) ?? ""),
              (1...12).contains(grade) else { return nil }
        return grade
    }

    private static func firstYearPair(in text: String) -> (Int, Int)? {
        guard let match = firstMatch(yearPattern, in: text),
              let first = Int(capture(1, of: match, in: text) ?? ""),
              let second = Int(capture(2, of: match, in: text) ?? "") else { return nil }
        return (first, second)
    }

    private static func digitRun(in text: String) -> String? {
        guard let match = firstMatch(digitPattern, in: text) else { return nil }
        return capture(0, of: match, in: text)
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func capture(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}
