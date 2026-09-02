import CoreGraphics
import Foundation

/// Draws a symbol into a bitmap. The app draws its barcodes in SwiftUI so they
/// stay vector-sharp at any scale; this exists so tests can hand a real image
/// back to Vision and prove the thing actually decodes.
public enum Code39Renderer {

    /// Black bars on an opaque white ground, with quiet zones included.
    ///
    /// Sizes are in pixels and integral on purpose: a bar that starts on a
    /// fractional pixel is a blurred bar.
    public static func makeImage(symbol: Code39.Symbol,
                                 moduleWidthPixels: Int,
                                 barHeightPixels: Int,
                                 quietZoneModules: Int = Code39.quietZoneModules) -> CGImage? {
        let moduleWidth = max(1, moduleWidthPixels)
        let height = max(1, barHeightPixels)
        let totalModules = symbol.moduleCount + 2 * max(0, quietZoneModules)
        let width = totalModules * moduleWidth

        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(false)
        context.setFillColor(gray: 0, alpha: 1)

        // Coalesce neighbouring bar modules into one rectangle so adjacent wide
        // and narrow bars never show a seam.
        var index = 0
        while index < symbol.modules.count {
            guard symbol.modules[index] else {
                index += 1
                continue
            }
            var run = 1
            while index + run < symbol.modules.count, symbol.modules[index + run] {
                run += 1
            }
            let x = (max(0, quietZoneModules) + index) * moduleWidth
            context.fill(CGRect(x: x, y: 0, width: run * moduleWidth, height: height))
            index += run
        }

        return context.makeImage()
    }
}
