#if DEBUG
import Foundation

/// Resolve the simulated school day, but give WidgetKit and system timers real dates.
public struct WidgetDebugClock: Sendable {
    public let offset: TimeInterval

    public init(offset: TimeInterval = 0) {
        self.offset = offset.isFinite ? offset : 0
    }

    public func scheduleDate(for date: Date) -> Date {
        date.addingTimeInterval(offset)
    }

    public func realDate(for date: Date) -> Date {
        date.addingTimeInterval(-offset)
    }

    public func realInterval(for interval: ClosedRange<Date>) -> ClosedRange<Date> {
        realDate(for: interval.lowerBound)...realDate(for: interval.upperBound)
    }
}
#endif
