import CoreGraphics
import Foundation

/// Finds the student photo on the page without face detection.
///
/// Vision's face detector, like its barcode detector, cannot be created in the
/// iOS Simulator, and it can also simply miss a face behind glasses or a strong
/// backlight. The photo on a Student Profile page has a shape no other element
/// has: a solid, portrait-ish, *photographic* block — many colours, unlike the
/// flat navigation bar — sitting in the upper part of an otherwise white page.
/// That is enough to find it geometrically.
enum PhotoRegionFinder {

    /// The photo's bounds in image coordinates, origin top left.
    ///
    /// - Parameter above: a y in image coordinates to stop at — the "Student
    ///   Number" label, when recognition found it. The photo is always above it
    ///   and the barcode always below, which is what keeps a dense patch of bars
    ///   from being read as a portrait.
    static func locate(in image: CGImage, above limit: CGFloat? = nil) -> CGRect? {
        let columns = 96
        guard let grid = Grid(image: image, columns: columns) else { return nil }

        var visited = [Bool](repeating: false, count: grid.columns * grid.rows)
        // Skip the status and navigation bars at the very top.
        let firstRow = Int(Double(grid.rows) * 0.06)
        let ceiling = limit.map { Int($0 / grid.cellHeight) } ?? Int(Double(grid.rows) * 0.60)
        // A limit above the navigation bars leaves nothing to search, which is a
        // photo not found rather than an inverted range.
        let lastRow = max(firstRow, min(ceiling, Int(Double(grid.rows) * 0.60)))

        var best: (rect: CGRect, area: Int)?
        for row in firstRow..<min(lastRow, grid.rows) {
            for column in 0..<grid.columns {
                let index = row * grid.columns + column
                guard !visited[index], grid.isInk[index] else { continue }
                let blob = grid.flood(from: index, visited: &visited)
                guard let rect = qualify(blob, in: grid) else { continue }
                if best == nil || blob.count > best!.area {
                    best = (rect, blob.count)
                }
            }
        }
        return best?.rect
    }

    /// A block only counts as the photo if it is solid, portrait-shaped, big but
    /// not page-wide, and visibly photographic.
    private static func qualify(_ blob: [Int], in grid: Grid) -> CGRect? {
        guard blob.count >= 12 else { return nil }

        var minColumn = grid.columns, maxColumn = 0, minRow = grid.rows, maxRow = 0
        for index in blob {
            let row = index / grid.columns
            let column = index % grid.columns
            minColumn = min(minColumn, column); maxColumn = max(maxColumn, column)
            minRow = min(minRow, row); maxRow = max(maxRow, row)
        }
        let cellsWide = maxColumn - minColumn + 1
        let cellsTall = maxRow - minRow + 1

        // Wide, thin runs are text lines and banners, not photographs.
        let aspect = Double(cellsWide) / Double(cellsTall)
        guard (0.4...1.35).contains(aspect) else { return nil }
        guard Double(cellsWide) / Double(grid.columns) >= 0.08,
              Double(cellsWide) / Double(grid.columns) <= 0.60 else { return nil }
        // A photo fills its bounding box; a glyph or a logo does not.
        guard Double(blob.count) / Double(cellsWide * cellsTall) >= 0.80 else { return nil }
        guard grid.isPhotographic(minColumn...maxColumn, minRow...maxRow) else { return nil }
        // A barcode is the one other solid, portrait-ish, high-variance block on
        // the page. It gives itself away by being made of vertical stripes:
        // every column is near-constant top to bottom, which no photograph is.
        guard !grid.isVerticallyStriped(minColumn...maxColumn, minRow...maxRow) else { return nil }

        return CGRect(x: Double(minColumn) * grid.cellWidth,
                      y: Double(minRow) * grid.cellHeight,
                      width: Double(cellsWide) * grid.cellWidth,
                      height: Double(cellsTall) * grid.cellHeight)
    }

    // MARK: - Coarse grid

    /// A heavily downsampled copy of the page. Averaging into cells throws away
    /// the text and leaves the block structure, which is what matters here.
    private struct Grid {
        let columns: Int
        let rows: Int
        let cellWidth: Double
        let cellHeight: Double
        let isInk: [Bool]
        private let luminance: [Double]

        init?(image: CGImage, columns: Int) {
            let rows = max(1, Int(Double(columns) * Double(image.height) / Double(image.width)))
            var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
            let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(data: raw.baseAddress,
                                              width: columns,
                                              height: rows,
                                              bitsPerComponent: 8,
                                              bytesPerRow: columns * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.interpolationQuality = .medium
                context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
                return true
            }
            guard drew else { return nil }

            var isInk = [Bool](repeating: false, count: columns * rows)
            var luminance = [Double](repeating: 0, count: columns * rows)
            for index in 0..<(columns * rows) {
                let red = Double(pixels[index * 4])
                let green = Double(pixels[index * 4 + 1])
                let blue = Double(pixels[index * 4 + 2])
                let high = max(red, green, blue)
                let low = min(red, green, blue)
                luminance[index] = 0.299 * red + 0.587 * green + 0.114 * blue
                // Anything that is not close to page white: darker, or coloured.
                isInk[index] = high < 238 || (high - low) > 26
            }

            self.columns = columns
            self.rows = rows
            self.cellWidth = Double(image.width) / Double(columns)
            self.cellHeight = Double(image.height) / Double(rows)
            self.isInk = isInk
            self.luminance = luminance
        }

        func flood(from start: Int, visited: inout [Bool]) -> [Int] {
            var stack = [start]
            var blob: [Int] = []
            visited[start] = true
            while let index = stack.popLast() {
                blob.append(index)
                let row = index / columns
                let column = index % columns
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nextColumn = column + dx
                    let nextRow = row + dy
                    guard nextColumn >= 0, nextColumn < columns,
                          nextRow >= 0, nextRow < rows else { continue }
                    let next = nextRow * columns + nextColumn
                    guard !visited[next], isInk[next] else { continue }
                    visited[next] = true
                    stack.append(next)
                }
            }
            return blob
        }

        /// True when brightness barely changes down each column while changing a
        /// lot across them — the signature of a barcode.
        func isVerticallyStriped(_ columnRange: ClosedRange<Int>, _ rowRange: ClosedRange<Int>) -> Bool {
            guard rowRange.count > 3 else { return false }
            var deviations: [Double] = []
            for column in columnRange {
                let values = rowRange.map { luminance[$0 * columns + column] }
                let mean = values.reduce(0, +) / Double(values.count)
                let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
                deviations.append(variance.squareRoot())
            }
            let average = deviations.reduce(0, +) / Double(deviations.count)
            return average < 7
        }

        /// A photograph varies in brightness across its area; a filled banner or
        /// a solid swatch does not.
        func isPhotographic(_ columnRange: ClosedRange<Int>, _ rowRange: ClosedRange<Int>) -> Bool {
            var values: [Double] = []
            for row in rowRange {
                for column in columnRange {
                    values.append(luminance[row * columns + column])
                }
            }
            guard values.count > 3 else { return false }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
            return variance.squareRoot() > 9
        }
    }
}
