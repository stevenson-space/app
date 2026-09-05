import CoreGraphics
import Foundation
import Testing
@testable import StudentIDKit

/// The package's own reader, which is what runs wherever Vision's barcode
/// detector is unavailable — the iOS Simulator, most importantly.
@Suite struct Code39DecoderTests {

    private func image(_ payload: String,
                       moduleWidthPixels: Int = 6,
                       barHeightPixels: Int = 200,
                       appendCheckDigit: Bool = false) throws -> CGImage {
        let symbol = try Code39.encode(payload, appendCheckDigit: appendCheckDigit)
        return try #require(Code39Renderer.makeImage(symbol: symbol,
                                                     moduleWidthPixels: moduleWidthPixels,
                                                     barHeightPixels: barHeightPixels))
    }

    @Test(arguments: ["59435", "104829", "0001", "12345678"])
    func readsBackWhatTheEncoderDrew(payload: String) throws {
        #expect(try Code39Decoder.decode(image(payload)).first == payload)
    }

    @Test(arguments: [2, 3, 5, 7, 12])
    func readsEveryModuleWidthTheAppCanDraw(moduleWidthPixels: Int) throws {
        let rendered = try image("59435", moduleWidthPixels: moduleWidthPixels,
                                 barHeightPixels: max(60, moduleWidthPixels * 30))
        #expect(Code39Decoder.decode(rendered).first == "59435")
    }

    @Test func readsLettersAndPunctuationToo() throws {
        #expect(try Code39Decoder.decode(image("AB-12.C")).first == "AB-12.C")
    }

    @Test func agreesWithTheEncoderAboutTheCheckDigit() throws {
        // The drawn symbol carries the check character, so a plain reader sees
        // it as part of the payload.
        #expect(try Code39Decoder.decode(image("59435", appendCheckDigit: true)).first == "59435Q")
    }

    @Test func acceptsIntercharacterGapsWiderThanNarrowElements() throws {
        // ISO/IEC 16388 section 4.4 permits a 3X intercharacter gap. Applying
        // the character's narrow/wide cutoff to these gaps would reject it.
        let symbol = try Code39.encode("59435")
        var modules: [Bool] = []
        for (index, module) in symbol.modules.enumerated() {
            modules.append(module)
            if index % 16 == 15 { modules.append(contentsOf: [false, false]) }
        }
        let widened = Code39.Symbol(payload: symbol.payload, modules: modules)
        let rendered = try #require(Code39Renderer.makeImage(symbol: widened, moduleWidthPixels: 5, barHeightPixels: 150))
        #expect(Code39Decoder.decode(rendered).first == "59435")
    }

    @Test func findsTheSymbolInsideAFullPage() {
        #expect(Code39Decoder.decode(SyntheticProfile.image()).first == "59435")
    }

    @Test func readsBlackBarsOnATransparentBackground() throws {
        let opaque = try image("59435")
        let transparent = try #require(opaque.copy(maskingColorComponents: [255, 255]))
        let buffer = try #require(ImageBuffer(transparent))
        #expect(buffer.pixel(x: 0, y: 0) == 255)
        #expect(Code39Decoder.decode(transparent).first == "59435")
    }

    @Test func readsNothingFromAPageWithNoBarcode() {
        var options = SyntheticProfile.Options()
        options.barcodePayload = nil
        #expect(Code39Decoder.decode(SyntheticProfile.image(options)).isEmpty)
    }

    @Test func readsNothingFromABlankImage() throws {
        let context = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        #expect(Code39Decoder.decode(try #require(context.makeImage())).isEmpty)
    }

    @Test func prefersThePayloadTheMostScanlinesAgreeOn() throws {
        // A tall symbol is read on many lines; anything spurious is read on few.
        let decoded = Code39Decoder.decode(try image("59435", barHeightPixels: 400))
        #expect(decoded.first == "59435")
    }
}
