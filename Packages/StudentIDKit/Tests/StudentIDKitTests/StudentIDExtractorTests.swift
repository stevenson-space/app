import CoreGraphics
import Foundation
import Testing
@testable import StudentIDKit

/// End-to-end through real Vision: a rendered page in, a finished card out.
/// The parser's own edge cases live in `ProfileTextParserTests`, which needs no
/// OCR; these cover the wiring and the refusals.
@Suite(.serialized) struct StudentIDExtractorTests {

    @Test func readsTheNumberNameGradeAndYearFromAProfilePage() async throws {
        let extraction = try await StudentIDExtractor.extract(from: SyntheticProfile.image())
        #expect(extraction.card.idNumber == "59435")
        #expect(extraction.card.barcodePayload == "59435")
        #expect(extraction.card.fullName == "Riley Vasquez")
        #expect(extraction.card.gradeLevel == 12)
        #expect(extraction.card.schoolYearStart == 2026)
        #expect(!extraction.warnings.contains(.printedNumberNotFound))
        // No real face to detect, so this is the geometric fallback finding the
        // photo by its shape on the page.
        #expect(extraction.photoJPEG != nil)
        #expect(!extraction.warnings.contains(.photoNotFound))
    }

    @Test func reportsAMissingPhotoRatherThanFailing() async throws {
        var options = SyntheticProfile.Options()
        options.includePhoto = false
        let extraction = try await StudentIDExtractor.extract(from: SyntheticProfile.image(options))
        #expect(extraction.card.idNumber == "59435")
        #expect(extraction.photoJPEG == nil)
        #expect(extraction.warnings.contains(.photoNotFound))
    }

    @Test func acceptsASixDigitNumber() async throws {
        var options = SyntheticProfile.Options()
        options.number = "104829"
        options.barcodePayload = "104829"
        let extraction = try await StudentIDExtractor.extract(from: SyntheticProfile.image(options))
        #expect(extraction.card.idNumber == "104829")
    }

    @Test func stillSucceedsWhenTheNameCannotBeRead() async throws {
        var options = SyntheticProfile.Options()
        options.name = nil
        let extraction = try await StudentIDExtractor.extract(from: SyntheticProfile.image(options))
        #expect(extraction.card.idNumber == "59435")
        #expect(extraction.card.fullName == nil)
        #expect(extraction.warnings.contains(.nameNotFound))
    }

    @Test func honoursTheEndedBadgeWhenEnrollmentsAreListedOutOfOrder() async throws {
        var options = SyntheticProfile.Options()
        options.endedEnrollmentFirst = true
        let extraction = try await StudentIDExtractor.extract(from: SyntheticProfile.image(options))
        #expect(extraction.card.gradeLevel == 12)
    }

    @Test func refusesAScreenshotWithNoBarcode() async {
        var options = SyntheticProfile.Options()
        options.barcodePayload = nil
        await #expect(throws: StudentIDImportError.barcodeNotFound) {
            try await StudentIDExtractor.extract(from: SyntheticProfile.image(options))
        }
    }

    @Test func refusesWhenTheBarcodeDisagreesWithThePrintedNumber() async {
        var options = SyntheticProfile.Options()
        options.number = "59435"
        options.barcodePayload = "11111"
        await #expect(throws: StudentIDImportError.numberMismatch(barcode: "11111", printed: "59435")) {
            try await StudentIDExtractor.extract(from: SyntheticProfile.image(options))
        }
    }

    @Test func refusesABarcodeThatDoesNotCarryANumber() async {
        var options = SyntheticProfile.Options()
        options.number = nil
        options.barcodePayload = "ABCDEF"
        await #expect(throws: StudentIDImportError.self) {
            try await StudentIDExtractor.extract(from: SyntheticProfile.image(options))
        }
    }

    @Test func refusesABarcodeFromSomewhereOtherThanInfiniteCampus() async {
        await #expect(throws: StudentIDImportError.notAStudentProfile) {
            try await StudentIDExtractor.extract(from: SyntheticProfile.bareBarcode(payload: "59435"))
        }
    }

    @Test func refusesAFileThatIsNotAnImage() async {
        await #expect(throws: StudentIDImportError.unreadableImage) {
            try await StudentIDExtractor.extract(from: Data("not an image".utf8))
        }
    }

    @Test func decodesFromEncodedImageDataToo() async throws {
        let data = SyntheticProfile.pngData(SyntheticProfile.image())
        let extraction = try await StudentIDExtractor.extract(from: data)
        #expect(extraction.card.idNumber == "59435")
    }

    @Test func framesAPortraitCropAroundADetectedFace() {
        // Head-and-shoulders framing: wider and taller than the face, and the
        // face sits above centre so there is room for shoulders.
        let size = CGSize(width: 1320, height: 2868)
        let face = CGRect(x: 120, y: 560, width: 200, height: 260)
        let crop = StudentIDExtractor.portraitCrop(around: face, in: size)

        #expect(crop.width > face.width)
        #expect(crop.height > face.height)
        #expect(crop.midY > face.midY)
        #expect(CGRect(origin: .zero, size: size).contains(crop))
    }

    @Test func trimsMarginOffTheCorrectEdges() {
        // A stripe of white along only the top: the trim must take it off the
        // top, not the bottom. Reading the pixel buffer upside down would pass
        // a symmetric test and quietly crop the wrong end of the photo.
        let context = CGContext(data: nil, width: 200, height: 400, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 400))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        // Bottom-up drawing: the lower 320pt of the context is the *bottom* of
        // the image, leaving 80pt of white across the top.
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 320))
        let image = context.makeImage()!

        let trimmed = StudentIDExtractor.trimmingPageMargin(
            CGRect(x: 0, y: 0, width: 200, height: 400), in: image)
        #expect(abs(trimmed.minY - 80) <= 6)
        #expect(abs(trimmed.maxY - 400) <= 6)
    }

    @Test func trimsTheWhitePageMarginOffAnOvershotCrop() throws {
        // A coloured photo on a white page: the crop overshoots to the right and
        // below, exactly the way expanding around a face box does.
        let context = CGContext(data: nil, width: 400, height: 400, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        context.setFillColor(red: 0.33, green: 0.50, blue: 0.60, alpha: 1)
        // Bottom-up drawing: this is the top-left 240x300 region of the image.
        context.fill(CGRect(x: 0, y: 100, width: 240, height: 300))
        let image = context.makeImage()!

        // Overshoot by 60pt on the right and below — within the quarter-of-a-side
        // the scan is allowed to reclaim.
        let trimmed = StudentIDExtractor.trimmingPageMargin(
            CGRect(x: 0, y: 0, width: 300, height: 360), in: image)
        // The coloured region is 240x300 at the top left of the image.
        #expect(abs(trimmed.width - 240) <= 6)
        #expect(abs(trimmed.height - 300) <= 6)
        #expect(trimmed.minX <= 6)
        #expect(trimmed.minY <= 6)
    }

    @Test func leavesACropWithNoMarginAlone() {
        let context = CGContext(data: nil, width: 300, height: 300, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        let image = context.makeImage()!

        let rect = CGRect(x: 0, y: 0, width: 300, height: 300)
        #expect(StudentIDExtractor.trimmingPageMargin(rect, in: image) == rect)
    }

    @Test func keepsTheCropInsideTheImageForAFaceNearTheEdge() {
        let size = CGSize(width: 1320, height: 2868)
        let crop = StudentIDExtractor.portraitCrop(
            around: CGRect(x: 4, y: 8, width: 200, height: 260), in: size)
        #expect(CGRect(origin: .zero, size: size).contains(crop))
        #expect(crop.width > 100)
    }
}
