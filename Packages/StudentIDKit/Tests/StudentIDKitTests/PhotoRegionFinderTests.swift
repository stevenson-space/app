import CoreGraphics
import Foundation
import Testing
@testable import StudentIDKit

/// Locating the photo without face detection — the path that runs in the
/// Simulator, and whenever a face simply is not found.
@Suite struct PhotoRegionFinderTests {

    @Test func findsThePhotoBlockOnAProfilePage() throws {
        let region = try #require(PhotoRegionFinder.locate(in: SyntheticProfile.image()))
        // Drawn at (60, 700) sized 300x420 on a 1320x2868 page. A cell is about
        // 14pt, so a cell of slack on each edge is expected.
        #expect(abs(region.minX - 60) < 30)
        #expect(abs(region.minY - 700) < 30)
        #expect(abs(region.width - 300) < 40)
        #expect(abs(region.height - 420) < 40)
    }

    @Test func findsNothingWhenThePageHasNoPhoto() {
        var options = SyntheticProfile.Options()
        options.includePhoto = false
        #expect(PhotoRegionFinder.locate(in: SyntheticProfile.image(options)) == nil)
    }

    @Test func ignoresAFlatPageWideBanner() throws {
        // The navigation bar is big, solid, and coloured — everything the photo
        // is, except that it is page-wide and one flat colour.
        let context = CGContext(data: nil, width: 800, height: 1600, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 1600))
        context.setFillColor(red: 0.55, green: 0.78, blue: 0.25, alpha: 1)
        context.fill(CGRect(x: 0, y: 1300, width: 800, height: 200))
        #expect(PhotoRegionFinder.locate(in: try #require(context.makeImage())) == nil)
    }

    @Test func neverMistakesTheBarcodeForAPortrait() throws {
        // Work at the finder's grid resolution. Both shades count as ink, as
        // densely packed bars do after downsampling. The blob has portrait
        // proportions, full coverage, and plenty of brightness variance.
        func stripedBlock(vertical: Bool) throws -> CGImage {
            let context = try #require(CGContext(data: nil, width: 96, height: 192,
                                                bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 192))
            for index in 0..<(vertical ? 24 : 32) {
                context.setFillColor(gray: index.isMultiple(of: 2) ? 0.15 : 0.7, alpha: 1)
                context.fill(CGRect(x: 24 + (vertical ? index : 0),
                                    y: 128 + (vertical ? 0 : index),
                                    width: vertical ? 1 : 24, height: vertical ? 32 : 1))
            }
            return try #require(context.makeImage())
        }
        // The same shape and shades qualify when variation runs down columns.
        #expect(PhotoRegionFinder.locate(in: try stripedBlock(vertical: false))
                == CGRect(x: 24, y: 32, width: 24, height: 32))
        #expect(PhotoRegionFinder.locate(in: try stripedBlock(vertical: true)) == nil)
    }

    @Test func stopsAtTheLimitItIsGiven() {
        // With the ceiling above the photo, there is nothing left to find.
        #expect(PhotoRegionFinder.locate(in: SyntheticProfile.image(), above: 600) == nil)
    }
}
