import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import StudentIDKit

/// Builds a stand-in for the Infinite Campus Student Profile page.
///
/// Synthetic on purpose: a real screenshot carries a real student's name, number,
/// and face, and none of that belongs in a repository. This reproduces the page's
/// *structure* — which is all the parser keys off — with invented values.
enum SyntheticProfile {

    struct Options {
        var name: String? = "Riley Vasquez"
        var number: String? = "59435"
        var barcodePayload: String? = "59435"
        var enrollmentYear: String? = "26-27"
        var grade: Int? = 12
        var includeEndedSummerEnrollment = true
        /// Puts the ended summer enrollment first, so "the first grade on the
        /// page" is the wrong answer and the ENDED badge has to be honoured.
        var endedEnrollmentFirst = false
    }

    static func image(_ options: Options = Options()) -> CGImage {
        let width = 1320
        let height = 2868
        let context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Green navigation bar, like the app chrome above the content.
        context.setFillColor(red: 0.55, green: 0.78, blue: 0.25, alpha: 1)
        context.fill(CGRect(x: 0, y: height - 350, width: width, height: 180))

        var cursor: CGFloat = 420
        draw("Student Profile", in: context, canvasHeight: height, at: CGPoint(x: 48, y: cursor), size: 46)
        cursor += 130
        draw("0 Items in Cart      $0.00", in: context, canvasHeight: height, at: CGPoint(x: 48, y: cursor), size: 34)
        cursor += 140

        if let name = options.name {
            draw(name, in: context, canvasHeight: height, at: CGPoint(x: 520, y: cursor), size: 58)
        }
        cursor += 110

        draw("Enrollments", in: context, canvasHeight: height, at: CGPoint(x: 520, y: cursor), size: 36, bold: true)
        cursor += 70

        func drawEnrollment(_ suffix: String, ended: Bool) {
            let year = options.enrollmentYear ?? "26-27"
            draw("\(year) Adlai E Stevenson \(suffix)", in: context, canvasHeight: height,
                 at: CGPoint(x: 520, y: cursor), size: 36)
            cursor += 56
            if let grade = options.grade {
                draw("Grade \(grade)", in: context, canvasHeight: height,
                     at: CGPoint(x: 520, y: cursor), size: 36)
                cursor += 56
            }
            if ended {
                draw("ENDED", in: context, canvasHeight: height,
                     at: CGPoint(x: 520, y: cursor), size: 32)
                cursor += 66
            }
            cursor += 20
        }

        if options.endedEnrollmentFirst, options.includeEndedSummerEnrollment {
            drawEnrollment("Summer", ended: true)
            drawEnrollment("High S", ended: false)
        } else {
            drawEnrollment("High S", ended: false)
            if options.includeEndedSummerEnrollment {
                drawEnrollment("Summer", ended: true)
            }
        }

        cursor += 40
        draw("Student Number", in: context, canvasHeight: height,
             at: CGPoint(x: 520, y: cursor), size: 36, bold: true)
        cursor += 60
        if let number = options.number {
            draw(number, in: context, canvasHeight: height, at: CGPoint(x: 520, y: cursor), size: 40)
        }
        cursor += 140

        draw("Student Identification Barcode", in: context, canvasHeight: height,
             at: CGPoint(x: 48, y: cursor), size: 34, bold: true)
        cursor += 90

        if let payload = options.barcodePayload,
           let symbol = try? Code39.encode(payload),
           let barcode = Code39Renderer.makeImage(symbol: symbol, moduleWidthPixels: 5, barHeightPixels: 150) {
            let rect = CGRect(x: 48,
                              y: CGFloat(height) - cursor - 150,
                              width: CGFloat(barcode.width),
                              height: 150)
            context.draw(barcode, in: rect)
        }

        return context.makeImage()!
    }

    /// A Code 39 symbol alone on a white page — no profile text anywhere. Stands
    /// in for someone importing a barcode from somewhere else entirely.
    static func bareBarcode(payload: String) -> CGImage {
        let symbol = try! Code39.encode(payload)
        let barcode = Code39Renderer.makeImage(
            symbol: symbol, moduleWidthPixels: 5, barHeightPixels: 150)!
        let context = CGContext(data: nil, width: 1320, height: 900,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1320, height: 900))
        context.draw(barcode, in: CGRect(x: 100, y: 380,
                                         width: CGFloat(barcode.width), height: 150))
        return context.makeImage()!
    }

    static func pngData(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// `y` is the distance from the top of the canvas, matching how the page
    /// reads; CoreGraphics draws from the bottom, so it is flipped here.
    private static func draw(_ text: String,
                             in context: CGContext,
                             canvasHeight: Int,
                             at origin: CGPoint,
                             size: CGFloat,
                             bold: Bool = false) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        // CoreText attribute keys, so this compiles without AppKit or UIKit.
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: origin.x, y: CGFloat(canvasHeight) - origin.y - size)
        CTLineDraw(line, context)
    }
}

/// A text line positioned the way the parser expects: top-left origin.
func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 300, height: CGFloat = 40) -> TextLine {
    TextLine(text: text, frame: CGRect(x: x, y: y, width: width, height: height))
}
