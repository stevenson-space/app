import SwiftUI
import StudentIDKit

/// Draws a Code 39 symbol at a size a scanner can actually read.
///
/// Always black on white, never semantic colours: a barcode that inverts in dark
/// mode is a barcode that does not scan. The bars are drawn from a pixel-snapped
/// layout, so edges land on whole pixels instead of being feathered across two.
struct Code39BarcodeView: View {
    let payload: String
    var includeCheckDigit = false
    /// Width the symbol may occupy, quiet zones included.
    let availableWidth: CGFloat
    var maximumModuleWidth: CGFloat = 3
    var minimumBarHeight: CGFloat = 44
    var maximumBarHeight: CGFloat = 132

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let symbol = try? Code39.encode(payload, appendCheckDigit: includeCheckDigit),
            let layout = Code39Layout(moduleCount: symbol.totalModuleCount,
                                      availableWidth: availableWidth,
                                      displayScale: displayScale,
                                      maximumModuleWidth: maximumModuleWidth,
                                      minimumBarHeight: minimumBarHeight,
                                      maximumBarHeight: maximumBarHeight) {
            Canvas(opaque: true, rendersAsynchronously: false) { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                context.fill(barsPath(symbol: symbol, layout: layout, height: size.height),
                             with: .color(.black))
            }
            .frame(width: layout.symbolWidth, height: layout.barHeight)
            // The bars carry no meaning a screen reader can use; the number is
            // announced by the card instead.
            .accessibilityHidden(true)
        }
    }

    /// Runs of adjacent bar modules become one rectangle, so a wide bar is a
    /// single fill rather than three abutting ones that could show a seam.
    private func barsPath(symbol: Code39.Symbol, layout: Code39Layout, height: CGFloat) -> Path {
        var path = Path()
        let leading = CGFloat(Code39.quietZoneModules) * layout.moduleWidth
        for run in symbol.barRuns {
            path.addRect(CGRect(x: leading + CGFloat(run.lowerBound) * layout.moduleWidth,
                                y: 0,
                                width: CGFloat(run.count) * layout.moduleWidth,
                                height: height))
        }
        return path
    }
}
