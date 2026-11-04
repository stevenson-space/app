import SwiftUI
import ScheduleKit

extension DayTimeline {
    /// The physical period a span occupies ("3–4A", "4B", "2"), independent of
    /// the class name; nil for blocks outside the numbered periods.
    func periodLabel(for span: ResolvedSpan) -> String? {
        if let label = blocks.first(where: { span.blockIDs.contains($0.id) })?.spanLabel {
            return label
        }
        guard let number = span.periodID?.periodNumber else { return nil }
        return span.half.map { "\(number)\($0.rawValue)" } ?? String(number)
    }
}
