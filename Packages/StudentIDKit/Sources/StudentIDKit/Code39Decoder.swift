import CoreGraphics
import Foundation

/// Reads a Code 39 symbol out of an image without Vision.
///
/// Vision is the first choice, but its barcode detector cannot be created in the
/// iOS Simulator at all ("Failed to create barcode detector"), which would make
/// the whole feature untestable and unusable outside a physical device. This is
/// the inverse of `Code39` — measure the widths of the black and white runs
/// along a scanline, classify each as narrow or wide, and look the groups up in
/// the same table used to draw them — so it also covers the case where Vision is
/// present but declines to read a symbol it drew itself.
enum Code39Decoder {

    /// Every distinct payload found, most confident first.
    ///
    /// A symbol is many pixels tall, so a real one appears on many scanlines and
    /// a misread on one or two. Sorting by how many lines agree puts the real
    /// answer first.
    static func decode(_ image: CGImage, scanlines: Int = 96) -> [String] {
        guard let buffer = ImageBuffer(image) else { return [] }

        var tally: [String: Int] = [:]
        let step = max(1, buffer.height / max(scanlines, 1))
        for y in stride(from: 0, to: buffer.height, by: step) {
            for payload in decodeRow(buffer, y: y) {
                tally[payload, default: 0] += 1
            }
        }
        return tally.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.map(\.key)
    }

    // MARK: - One scanline

    private static func decodeRow(_ buffer: ImageBuffer, y: Int) -> [String] {
        let row = buffer.row(y)
        guard let low = row.min(), let high = row.max(), Int(high) - Int(low) > 64 else {
            return []   // Blank line: nothing to read.
        }
        let threshold = (Int(low) + Int(high)) / 2

        // Alternating runs of dark and light, in pixels.
        var runs: [(isDark: Bool, length: Int)] = []
        var isDark = Int(row[row.startIndex]) < threshold
        var length = 0
        for pixel in row {
            let dark = Int(pixel) < threshold
            if dark == isDark {
                length += 1
            } else {
                runs.append((isDark, length))
                isDark = dark
                length = 1
            }
        }
        runs.append((isDark, length))

        var payloads: [String] = []
        for start in runs.indices where runs[start].isDark {
            if let payload = decodeSymbol(runs, from: start) {
                payloads.append(payload)
            }
        }
        return payloads
    }

    /// A character is 9 runs; characters are separated by a single narrow run.
    private static func decodeSymbol(_ runs: [(isDark: Bool, length: Int)], from start: Int) -> String? {
        guard let first = character(runs, at: start), first == "*" else { return nil }

        var characters: [Character] = []
        var index = start + 10   // 9 elements plus the inter-character gap
        while index + 9 <= runs.count {
            guard let character = character(runs, at: index) else { return nil }
            if character == "*" {
                guard !characters.isEmpty else { return nil }
                return String(characters)
            }
            characters.append(character)
            // A symbol longer than this is not a student ID; bail rather than
            // walking the rest of the row.
            guard characters.count <= 32 else { return nil }
            index += 10
        }
        return nil
    }

    private static func character(_ runs: [(isDark: Bool, length: Int)], at index: Int) -> Character? {
        guard index + 9 <= runs.count, runs[index].isDark else { return nil }

        let group = runs[index..<(index + 9)]
        // Runs must alternate dark, light, dark, … within a character.
        for (offset, run) in group.enumerated() where run.isDark != offset.isMultiple(of: 2) {
            return nil
        }

        let lengths = group.map(\.length)
        guard let narrow = lengths.min(), let wide = lengths.max(), narrow > 0 else { return nil }
        // Every character mixes narrow and wide elements at roughly 1:3. Anything
        // outside that band is a run of unrelated content, not a character.
        guard wide >= narrow * 2, wide <= narrow * 5 else { return nil }

        let cutoff = (narrow + wide) / 2
        let pattern = lengths.map { $0 > cutoff }
        return Code39.character(for: pattern)
    }
}
