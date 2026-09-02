import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Reads a student ID out of an Infinite Campus Student Profile screenshot.
///
/// Only the barcode is required. The name, grade, school year, and photo are
/// best-effort: the barcode is what actually gets scanned, so a screenshot that
/// yields a number but not a name still produces a usable ID, with a warning
/// saying what was missed.
///
/// Nothing here touches the main actor — the package is compiled without
/// MainActor-by-default isolation, so the app (which is not) gets the whole
/// pipeline off the main thread simply by awaiting it.
public enum StudentIDExtractor {

    public static func extract(from imageData: Data) async throws -> StudentIDExtraction {
        guard let image = normalizedImage(from: imageData) else {
            throw StudentIDImportError.unreadableImage
        }
        return try await extract(from: image)
    }

    static func extract(from image: CGImage) async throws -> StudentIDExtraction {
        let size = CGSize(width: image.width, height: image.height)
        let lines = await recognizeText(in: image, size: size)
        let printedNumber = ProfileTextParser.printedStudentNumber(in: lines)

        let observations = try await detectBarcodes(in: image)
        guard !observations.isEmpty else { throw StudentIDImportError.barcodeNotFound }

        let candidates = observations.compactMap(Candidate.init)
        guard !candidates.isEmpty else {
            let raw = observations.compactMap(\.payloadString).first ?? ""
            throw StudentIDImportError.unsupportedBarcodePayload(raw)
        }

        // When the page shows the number in print too, trust the barcode that
        // agrees with it; a disagreement means the screenshot is a composite of
        // two different pages and must not be saved.
        let chosen = candidates.first { $0.payload == printedNumber } ?? candidates[0]
        if let printedNumber, printedNumber != chosen.payload {
            throw StudentIDImportError.numberMismatch(barcode: chosen.payload, printed: printedNumber)
        }

        // A bare Code 39 barcode from somewhere else is not a student ID.
        guard printedNumber != nil || ProfileTextParser.looksLikeProfilePage(lines) else {
            throw StudentIDImportError.notAStudentProfile
        }

        let name = ProfileTextParser.fullName(in: lines, imageHeight: size.height)
        let grade = ProfileTextParser.gradeLevel(in: lines)
        let year = ProfileTextParser.schoolYearStart(in: lines)
        let photo = await photoJPEG(from: image, size: size)

        var warnings: [StudentIDWarning] = []
        if name == nil { warnings.append(.nameNotFound) }
        if photo == nil { warnings.append(.photoNotFound) }
        if grade == nil { warnings.append(.gradeNotFound) }
        if year == nil { warnings.append(.schoolYearNotFound) }
        if printedNumber == nil { warnings.append(.printedNumberNotFound) }

        let card = StudentIDCard(
            idNumber: chosen.payload,
            barcodePayload: chosen.payload,
            requiresCheckDigit: chosen.requiresCheckDigit,
            fullName: name,
            gradeLevel: grade,
            schoolYearStart: year,
            importedAt: Date())

        return StudentIDExtraction(card: card, photoJPEG: photo, warnings: warnings)
    }

    // MARK: - Barcode

    private struct Candidate {
        let payload: String
        let requiresCheckDigit: Bool

        init?(_ observation: BarcodeObservation) {
            guard let raw = observation.payloadString else { return nil }
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "* \t\n"))
            guard StudentIDCard.isValidNumber(trimmed) else { return nil }
            payload = trimmed
            // A checksum symbology means the printed symbol carries a modulo-43
            // character that Vision strips from the payload. Re-encoding without
            // it would produce a different symbol than the school issued.
            requiresCheckDigit = observation.symbology == .code39Checksum
                || observation.symbology == .code39FullASCIIChecksum
        }
    }

    private static func detectBarcodes(in image: CGImage) async throws -> [BarcodeObservation] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum]
        do {
            return try await request.perform(on: image)
        } catch {
            throw StudentIDImportError.barcodeNotFound
        }
    }

    // MARK: - Text

    private static func recognizeText(in image: CGImage, size: CGSize) async -> [TextLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // A surname is not a dictionary word; correction does more harm than good.
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]

        guard let observations = try? await request.perform(on: image) else { return [] }
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let frame = observation.boundingBox.toImageCoordinates(size, origin: .upperLeft)
            return TextLine(text: text, frame: frame)
        }
    }

    // MARK: - Photo

    private static func photoJPEG(from image: CGImage, size: CGSize) async -> Data? {
        let request = DetectFaceRectanglesRequest()
        guard let faces = try? await request.perform(on: image) else { return nil }

        let boxes = faces
            .filter { $0.confidence >= 0.5 }
            .map { $0.boundingBox.toImageCoordinates(size, origin: .upperLeft) }
            .filter { $0.midY < size.height * 0.6 }
        guard let face = boxes.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return nil
        }

        // Expand around the face, then pull the edges back onto the photo. The
        // card's photo well fills and clips, so the crop keeps whatever aspect
        // the source photo has rather than being forced into one and losing the
        // top of the head.
        let expanded = portraitCrop(around: face, in: size)
        let crop = trimmingPageMargin(expanded, in: image)
        guard crop.width > 1, crop.height > 1, let cropped = image.cropping(to: crop) else {
            return nil
        }
        return jpegData(from: cropped)
    }

    /// Grows a face box into a head-and-shoulders portrait: the face sits a
    /// little above centre, the way an ID photo is framed.
    static func portraitCrop(around face: CGRect, in size: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: size)
        let width = face.width * 2.4
        let height = face.height * 2.9
        var rect = CGRect(x: face.midX - width / 2,
                          y: face.midY - height * 0.42,
                          width: width,
                          height: height)

        // Slide back inside the image before clipping, so a face near an edge
        // still gets a full-size crop rather than a sliver.
        rect = rect.offsetBy(dx: max(0, -rect.minX) - max(0, rect.maxX - size.width),
                             dy: max(0, -rect.minY) - max(0, rect.maxY - size.height))
        return rect.intersection(bounds).integral
    }

    /// Pulls each edge inward past rows and columns that are flat, near-white
    /// page background.
    ///
    /// A face box only says where the head is, so expanding around it always
    /// overshoots the photo and picks up the white page behind it. Each edge
    /// scans inward and takes the *deepest* margin line it finds, so a hairline
    /// divider partway through the margin does not stop the trim early. The scan
    /// is capped at a quarter of each side, which bounds the damage if a photo
    /// really does have pale edges.
    static func trimmingPageMargin(_ rect: CGRect, in image: CGImage) -> CGRect {
        guard let cropped = image.cropping(to: rect.integral),
              let buffer = grayscaleBuffer(cropped) else { return rect }

        let width = buffer.width
        let height = buffer.height
        guard width > 8, height > 8 else { return rect }

        // Mostly white, with a tolerance for the hairline rules and card borders
        // that run through an otherwise empty margin — being strict about those
        // stops the trim at the first divider and leaves the margin in place.
        func isMargin(_ samples: [UInt8]) -> Bool {
            guard !samples.isEmpty else { return false }
            let mean = samples.reduce(0) { $0 + Int($1) } / samples.count
            let dark = samples.filter { $0 < 200 }.count
            return mean > 235 && dark * 20 <= samples.count
        }
        func column(_ x: Int) -> [UInt8] {
            stride(from: 0, to: height, by: max(1, height / 64)).map { buffer.pixels[$0 * width + x] }
        }
        // A bitmap context stores rows top-down in memory even though its
        // coordinate system counts upward, so row 0 really is the top edge.
        func row(_ yFromTop: Int) -> [UInt8] {
            stride(from: 0, to: width, by: max(1, width / 64)).map {
                buffer.pixels[yFromTop * width + $0]
            }
        }

        func depth(cap: Int, line: (Int) -> [UInt8]) -> Int {
            var deepest = 0
            for index in 0..<max(cap, 0) where isMargin(line(index)) { deepest = index + 1 }
            return deepest
        }
        let left = depth(cap: width / 4) { column($0) }
        let right = depth(cap: width / 4) { column(width - 1 - $0) }
        let top = depth(cap: height / 4) { row($0) }
        let bottom = depth(cap: height / 4) { row(height - 1 - $0) }

        let trimmed = CGRect(x: rect.minX + CGFloat(left),
                             y: rect.minY + CGFloat(top),
                             width: rect.width - CGFloat(left + right),
                             height: rect.height - CGFloat(top + bottom))
        return trimmed.width > 16 && trimmed.height > 16 ? trimmed : rect
    }

    private static func grayscaleBuffer(_ image: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
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
        return drew ? (pixels, width, height) : nil
    }

    private static func jpegData(from image: CGImage,
                                 maxDimension: CGFloat = 600,
                                 quality: CGFloat = 0.9) -> Data? {
        let source = downscaled(image, maxDimension: maxDimension) ?? image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, source, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func downscaled(_ image: CGImage, maxDimension: CGFloat) -> CGImage? {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let width = Int((CGFloat(image.width) * scale).rounded())
        let height = Int((CGFloat(image.height) * scale).rounded())
        guard let context = CGContext(data: nil,
                                      width: max(width, 1),
                                      height: max(height, 1),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Decoding

    /// Decodes and, if the file carries an EXIF orientation, bakes it in — so
    /// every coordinate downstream lives in one space and no crop comes out
    /// sideways.
    static func normalizedImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        guard let orientation = CGImagePropertyOrientation(rawValue: raw), orientation != .up else {
            return image
        }
        return redrawn(image, orientation: orientation)
    }

    private static func redrawn(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let swapsAxes: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: swapsAxes = true
        default: swapsAxes = false
        }
        let size = swapsAxes ? CGSize(width: height, height: width) : CGSize(width: width, height: height)

        guard let context = CGContext(data: nil,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        // CGContext draws from the bottom left, so each case is the inverse of
        // the EXIF transform.
        switch orientation {
        case .up, .upMirrored:
            break
        case .down, .downMirrored:
            context.translateBy(x: size.width, y: size.height)
            context.rotate(by: .pi)
        case .left, .leftMirrored:
            context.translateBy(x: size.width, y: 0)
            context.rotate(by: .pi / 2)
        case .right, .rightMirrored:
            context.translateBy(x: 0, y: size.height)
            context.rotate(by: -.pi / 2)
        }
        switch orientation {
        case .upMirrored, .downMirrored:
            context.translateBy(x: width, y: 0)
            context.scaleBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            context.translateBy(x: height, y: 0)
            context.scaleBy(x: -1, y: 1)
        default:
            break
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
