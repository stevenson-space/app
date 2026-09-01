import SwiftUI
import StudentIDKit

struct Code39BarcodeView: View {
    let value: String
    var barHeight: CGFloat = 76

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let symbol = try? Code39Encoder.encode(value) {
            GeometryReader { proxy in
                let availableWidth = min(proxy.size.width, 360)
                let availablePixels = Int(floor(availableWidth * displayScale))
                let modulePixels = max(1, availablePixels / symbol.totalModules)
                let renderedPixels = modulePixels * symbol.totalModules
                let renderedWidth = CGFloat(renderedPixels) / displayScale
                let originPixels = floor((proxy.size.width * displayScale
                                          - CGFloat(renderedPixels)) / 2)
                let origin = originPixels / displayScale

                Canvas(opaque: true, colorMode: .nonLinear, rendersAsynchronously: false) {
                    context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    context.withCGContext { graphicsContext in
                        graphicsContext.setShouldAntialias(false)
                        graphicsContext.setAllowsAntialiasing(false)
                        graphicsContext.setFillColor(UIColor.black.cgColor)

                        var x = origin
                        for run in symbol.runs {
                            let width = CGFloat(run.modules * modulePixels) / displayScale
                            if run.isBar {
                                graphicsContext.fill(CGRect(x: x, y: 0,
                                                            width: width, height: barHeight))
                            }
                            x += width
                        }
                    }
                }
                .frame(width: proxy.size.width, height: barHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Code 39 barcode for student number \(symbol.payload)")
                .accessibilityValue("Barcode width \(Int(renderedWidth)) points")
            }
            .frame(height: barHeight)
        } else {
            ContentUnavailableView(
                "Barcode unavailable",
                systemImage: "barcode.viewfinder",
                description: Text("Check the student number and try again.")
            )
            .frame(height: barHeight)
        }
    }
}

#Preview("Code 39") {
    Code39BarcodeView(value: "12345")
        .padding()
        .background(.white)
}
