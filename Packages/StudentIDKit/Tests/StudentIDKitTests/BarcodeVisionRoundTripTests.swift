import CoreGraphics
import Testing
import Vision
@testable import StudentIDKit

@Suite struct BarcodeVisionRoundTripTests {
    @Test func renderedValuesDecodeAsCode39() throws {
        for value in ["12345", "0123456789", "CODE-39"] {
            let image = try render(value)
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.code39]
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

            #expect(request.results?.first?.payloadStringValue == value)
        }
    }

    private func render(_ value: String) throws -> CGImage {
        let symbol = try Code39Encoder.encode(value)
        let modulePixels = 4
        let width = symbol.totalModules * modulePixels
        let height = 160
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.setShouldAntialias(false)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0, alpha: 1)

        var x = 0
        for run in symbol.runs {
            let runWidth = run.modules * modulePixels
            if run.isBar {
                context.fill(CGRect(x: x, y: 0, width: runWidth, height: height))
            }
            x += runWidth
        }

        return try #require(context.makeImage())
    }
}
