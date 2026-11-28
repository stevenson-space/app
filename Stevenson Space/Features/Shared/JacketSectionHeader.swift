import SwiftUI
import ScheduleKit

/// A form section header set as a jacket label.
struct JacketSectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .jacketLabel()
            .foregroundStyle(Jacket.ink2)
    }
}
