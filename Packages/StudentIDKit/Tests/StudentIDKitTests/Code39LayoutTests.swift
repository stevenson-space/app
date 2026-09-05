import CoreGraphics
import Foundation
import Testing
@testable import StudentIDKit

/// Snapped module widths come out of division, so compare them the way
/// floating point wants to be compared.
private func isClose(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 1e-9) -> Bool {
    abs(lhs - rhs) < tolerance
}

@Suite struct Code39LayoutTests {

    /// The card's barcode well on an iPhone 17: 402pt screen, 16pt page margins,
    /// 18pt inset inside the card.
    private let cardWidth: CGFloat = 402 - 32 - 36
    /// Full-screen scan mode: 402pt screen, 20pt margins.
    private let scanWidth: CGFloat = 402 - 40

    private func moduleCount(digits: Int) -> Int {
        16 * digits + 31 + 2 * Code39.quietZoneModules
    }

    @Test(arguments: [1.0, 2.0, 3.0])
    func moduleWidthLandsOnWholePixels(scale: CGFloat) throws {
        let layout = try #require(Code39Layout(moduleCount: moduleCount(digits: 5),
                                  availableWidth: cardWidth,
                                  displayScale: scale))
        let pixels = layout.moduleWidth * scale
        #expect(abs(pixels - pixels.rounded()) < 1e-9,
                "\(layout.moduleWidth)pt is \(pixels) pixels at \(scale)x")
        #expect(pixels >= 1)
    }

    @Test(arguments: [4, 5, 6, 7, 8])
    func symbolNeverOutgrowsTheSpaceItWasGiven(digits: Int) throws {
        for width in [cardWidth, scanWidth, 200, 120] as [CGFloat] {
            let layout = try #require(Code39Layout(moduleCount: moduleCount(digits: digits),
                                      availableWidth: width,
                                      displayScale: 3))
            #expect(layout.symbolWidth <= width + 1e-9,
                    "\(digits) digits overflowed \(width)pt by \(layout.symbolWidth - width)")
        }
    }

    @Test func fiveDigitNumberFillsTheCardWithChunkyBars() throws {
        let layout = try #require(Code39Layout(moduleCount: moduleCount(digits: 5),
                                  availableWidth: cardWidth,
                                  displayScale: 3))
        // Seven device pixels per module: about 0.8mm, three times the module
        // width of the printed card, which is the right direction for a screen.
        #expect(isClose(layout.moduleWidth, 7.0 / 3.0))
        #expect(layout.symbolWidth > 300)
    }

    @Test func sixDigitNumberStillFitsTheCard() throws {
        let layout = try #require(Code39Layout(moduleCount: moduleCount(digits: 6),
                                  availableWidth: cardWidth,
                                  displayScale: 3))
        #expect(isClose(layout.moduleWidth, 2.0))
        #expect(isClose(layout.symbolWidth, 294))
    }

    @Test func scanModeGoesWiderThanTheCard() throws {
        let card = try #require(Code39Layout(moduleCount: moduleCount(digits: 5),
                                availableWidth: cardWidth, displayScale: 3))
        let scan = try #require(Code39Layout(moduleCount: moduleCount(digits: 5),
                                availableWidth: scanWidth, displayScale: 3,
                                maximumModuleWidth: 4, minimumBarHeight: 120))
        #expect(scan.moduleWidth > card.moduleWidth)
        #expect(isClose(scan.barHeight, 120))
    }

    @Test func capsTheModuleWidthSoWideScreensDoNotProduceAbsurdBars() throws {
        let layout = try #require(Code39Layout(moduleCount: moduleCount(digits: 5),
                                  availableWidth: 4000,
                                  displayScale: 2,
                                  maximumModuleWidth: 3))
        #expect(isClose(layout.moduleWidth, 3))
    }

    @Test func barHeightMeetsTheFifteenPercentGuideline() throws {
        for digits in 4...8 {
            let layout = try #require(Code39Layout(moduleCount: moduleCount(digits: digits),
                                      availableWidth: cardWidth,
                                      displayScale: 3))
            #expect(layout.barHeight >= layout.symbolWidth * Code39Layout.barHeightRatio - 0.5,
                    "\(digits) digits: \(layout.barHeight)pt of \(layout.symbolWidth)pt")
        }
    }

    @Test func fitsEvenWhenTheSpaceForcesThinBars() throws {
        let layout = try #require(Code39Layout(moduleCount: moduleCount(digits: 8),
                                  availableWidth: 90,
                                  displayScale: 3))
        #expect(layout.symbolWidth <= 90)
    }

    @Test(arguments: [1.0, 2.0, 3.0])
    func refusesToClipQuietZonesWhenOnePixelPerModuleCannotFit(scale: CGFloat) throws {
        let count = moduleCount(digits: 5)
        let minimumWidth = CGFloat(count) / scale
        for width in [0, minimumWidth - 0.01] {
            #expect(Code39Layout(moduleCount: count, availableWidth: width, displayScale: scale) == nil)
        }
        let layout = try #require(Code39Layout(moduleCount: count,
                                              availableWidth: minimumWidth, displayScale: scale))
        #expect(isClose(layout.moduleWidth, 1 / scale))
        #expect(layout.symbolWidth <= minimumWidth)
    }
}
