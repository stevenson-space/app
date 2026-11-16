import SwiftUI

/// A running stitch: the rule between rows and sections.
public struct StitchRule: View {
    private let color: Color

    public init(_ color: Color) {
        self.color = color
    }

    public var body: some View {
        StitchLine()
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3.5]))
            .frame(height: 1.5)
            .accessibilityHidden(true)
    }
}

private struct StitchLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
