import CoreGraphics
import Foundation

/// How wide to draw one module, and how tall to draw the bars.
///
/// Two rules drive this. First, **fit**: the whole symbol, quiet zones included,
/// must sit inside the space available, or the edges get clipped and nothing
/// scans. Second, **pixel alignment**: the module width is snapped down to a whole
/// number of device pixels, so every bar edge lands on a pixel boundary and the
/// bars stay crisp instead of being smeared across two pixels by antialiasing —
/// blurred edges are the usual reason a screen-rendered barcode fails to read.
public struct Code39Layout: Equatable, Sendable {
    /// Points per module. Always an exact multiple of `1 / displayScale`.
    public let moduleWidth: CGFloat
    /// Points across the whole symbol, quiet zones included.
    public let symbolWidth: CGFloat
    /// Points tall for the bars.
    public let barHeight: CGFloat

    /// The symbology guide asks for bars at least 15% of the symbol's length.
    public static let barHeightRatio: CGFloat = 0.15

    public init(moduleCount: Int,
                availableWidth: CGFloat,
                displayScale: CGFloat,
                maximumModuleWidth: CGFloat = 3.0,
                minimumBarHeight: CGFloat = 44,
                maximumBarHeight: CGFloat = 132) {
        let scale = displayScale > 0 ? displayScale : 1
        let onePixel = 1 / scale
        let count = CGFloat(max(moduleCount, 1))

        // Widest module that still fits, snapped down to whole pixels. A symbol
        // is never allowed to grow past the space it was given, so a cramped
        // container yields thinner bars rather than clipped ones.
        let fitting = max(onePixel, ((availableWidth / count) * scale).rounded(.down) / scale)
        let capped = min(fitting, (maximumModuleWidth * scale).rounded(.down) / scale)

        moduleWidth = max(onePixel, capped)
        symbolWidth = moduleWidth * count

        let ideal = symbolWidth * Code39Layout.barHeightRatio
        let bounded = min(max(ideal, minimumBarHeight), max(minimumBarHeight, maximumBarHeight))
        barHeight = (bounded * scale).rounded() / scale
    }
}
