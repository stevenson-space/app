import SwiftUI
import ScheduleKit

extension View {
    /// Floating chrome over a ground: Liquid Glass on iOS 26, a material
    /// before it. Navigation layer only, never content.
    @ViewBuilder
    func floatingGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}
