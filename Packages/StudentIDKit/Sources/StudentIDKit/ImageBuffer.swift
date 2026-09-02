import CoreGraphics
import Foundation

/// An 8-bit grayscale copy of an image, rows stored top-down.
///
/// A bitmap context keeps its rows in memory from the top even though its
/// drawing coordinates count upward, so `pixel(x:y:)` here means what it looks
/// like it means: y counts down from the top edge.
struct ImageBuffer {
    let pixels: [UInt8]
    let width: Int
    let height: Int

    init?(_ image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        self.pixels = pixels
        self.width = width
        self.height = height
    }

    func pixel(x: Int, y: Int) -> UInt8 { pixels[y * width + x] }

    func row(_ y: Int) -> ArraySlice<UInt8> {
        pixels[(y * width)..<((y + 1) * width)]
    }
}
