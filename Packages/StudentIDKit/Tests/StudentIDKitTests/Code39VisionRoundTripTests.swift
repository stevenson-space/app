import CoreGraphics
import Foundation
import Testing
import Vision
@testable import StudentIDKit

/// The gate that matters: render the symbol the way the app renders it, hand the
/// pixels to a real barcode reader, and require the original number back. A
/// barcode that merely looks convincing is worthless.
@Suite(.serialized) struct Code39VisionRoundTripTests {

    private func decode(_ image: CGImage) async throws -> [String] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum]
        let observations = try await request.perform(on: image)
        return observations.compactMap(\.payloadString).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "* \t\n"))
        }
    }

    @Test(arguments: ["59435", "123456", "0001", "70012345"])
    func renderedSymbolDecodesBackToItsPayload(payload: String) async throws {
        let symbol = try Code39.encode(payload)
        let image = try #require(Code39Renderer.makeImage(
            symbol: symbol, moduleWidthPixels: 6, barHeightPixels: 200))
        #expect(try await decode(image).contains(payload))
    }

    @Test(arguments: [3, 4, 6, 9, 12])
    func decodesAcrossTheModuleWidthsTheAppCanProduce(moduleWidthPixels: Int) async throws {
        let symbol = try Code39.encode("59435")
        let height = max(60, moduleWidthPixels * symbol.totalModuleCount * 15 / 100)
        let image = try #require(Code39Renderer.makeImage(
            symbol: symbol, moduleWidthPixels: moduleWidthPixels, barHeightPixels: height))
        #expect(try await decode(image).contains("59435"))
    }

    @Test func decodesAtTheExactGeometryTheCardDraws() async throws {
        // iPhone 17 at 3x: 7px modules, 46pt bars.
        let symbol = try Code39.encode("59435")
        let layout = try #require(Code39Layout(moduleCount: symbol.totalModuleCount,
                                  availableWidth: 402 - 32 - 36,
                                  displayScale: 3))
        let image = try #require(Code39Renderer.makeImage(
            symbol: symbol,
            moduleWidthPixels: Int((layout.moduleWidth * 3).rounded()),
            barHeightPixels: Int((layout.barHeight * 3).rounded())))
        #expect(try await decode(image).contains("59435"))
    }

    @Test func decodesAtTheExactGeometryScanModeDraws() async throws {
        let symbol = try Code39.encode("59435")
        let layout = try #require(Code39Layout(moduleCount: symbol.totalModuleCount,
                                  availableWidth: 402 - 40,
                                  displayScale: 3,
                                  maximumModuleWidth: 4,
                                  minimumBarHeight: 120))
        let image = try #require(Code39Renderer.makeImage(
            symbol: symbol,
            moduleWidthPixels: Int((layout.moduleWidth * 3).rounded()),
            barHeightPixels: Int((layout.barHeight * 3).rounded())))
        #expect(try await decode(image).contains("59435"))
    }

    @Test func aSymbolCarryingACheckDigitDecodesToThePlainNumber() async throws {
        let symbol = try Code39.encode("59435", appendCheckDigit: true)
        let image = try #require(Code39Renderer.makeImage(
            symbol: symbol, moduleWidthPixels: 6, barHeightPixels: 200))
        // A checksum-aware reader strips the check character it validated.
        #expect(try await decode(image).contains { $0 == "59435" || $0 == "59435Q" })
    }
}
