import Foundation

/// A point-in-time answer shared by system actions. Uses physical blocks for
/// period identity, since the display timeline may merge several free periods.
public struct ScheduleInquiry: Sendable {
    public let timeline: DayTimeline
    public let state: MomentState
    public let currentPeriod: ResolvedBlock?
    public let currentClass: ResolvedBlock?
    /// The next academic class today; lunch, free time, and events are skipped.
    public let nextClass: ResolvedBlock?

    public init(at now: Date, inputs: ResolverInputs) {
        let timeline = resolveDay(DayKey(date: now), inputs: inputs)
        self.timeline = timeline
        self.state = momentState(at: now, in: timeline)
        let current = timeline.blocks.first { $0.start <= now && now < $0.end }
        self.currentPeriod = current
        self.currentClass = current.flatMap { Self.isClass($0) ? $0 : nil }
        self.nextClass = timeline.blocks.first { $0.start > now && Self.isClass($0) }
    }

    private static func isClass(_ block: ResolvedBlock) -> Bool {
        block.role == .classPeriod || block.role == .summerSchool
    }
}
