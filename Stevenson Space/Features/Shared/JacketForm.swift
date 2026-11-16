import SwiftUI
import ScheduleKit

extension View {
    /// A native grouped form on the jacket's lining: raised rows, the accent
    /// tint, stitched-label headers via `JacketSectionHeader`.
    func jacketForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Jacket.lining)
            .environment(\.jacketGround, .lining)
    }

    /// Rows of a section in a `jacketForm()`.
    func jacketRows() -> some View {
        listRowBackground(Jacket.raised)
    }
}
