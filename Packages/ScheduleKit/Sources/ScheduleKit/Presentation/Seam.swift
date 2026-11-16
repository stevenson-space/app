import SwiftUI

/// Progress as a seam: stitches turn gold as the block elapses. Decorative;
/// the countdown beside it carries the value for VoiceOver.
public struct Seam: View {
    private let fraction: Double
    private let on: Color
    private let off: Color
    private let stitches: Int
    private let height: CGFloat
    private let spacing: CGFloat

    public init(fraction: Double, on: Color, off: Color,
                stitches: Int = 30, height: CGFloat = 4, spacing: CGFloat = 3) {
        self.fraction = min(max(fraction, 0), 1)
        self.on = on
        self.off = off
        self.stitches = stitches
        self.height = height
        self.spacing = spacing
    }

    public var body: some View {
        let sewn = Int((fraction * Double(stitches)).rounded(.down))
        HStack(spacing: spacing) {
            ForEach(0..<stitches, id: \.self) { index in
                Capsule().fill(index < sewn ? on : off)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
