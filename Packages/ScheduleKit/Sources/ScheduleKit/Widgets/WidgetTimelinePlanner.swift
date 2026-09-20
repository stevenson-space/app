import Foundation

/// Widget-specific presentation of the existing state machine. The two timed
/// decorations (lead-in and finished) do not change period or passing semantics.
public struct WidgetScheduleEntry: Sendable {
    public let date: Date
    public let timeline: DayTimeline
    public let state: MomentState
    public let nextSchoolDay: DayTimeline?

    public init(date: Date, timeline: DayTimeline, state: MomentState, nextSchoolDay: DayTimeline?) {
        self.date = date
        self.timeline = timeline
        self.state = state
        self.nextSchoolDay = nextSchoolDay
    }

    public var isLeadIn: Bool {
        guard case .beforeSchool(let first) = state else { return false }
        return date >= first.start.addingTimeInterval(-15 * 60)
    }

    public var isFinished: Bool {
        guard case .afterSchool = state, let end = timeline.lastBell else { return false }
        return date < end.addingTimeInterval(5 * 60)
    }

    /// Apple renders the countdown within this closed interval, stopping at zero
    /// even if the OS delivers the following timeline entry late.
    public var countdownInterval: ClosedRange<Date>? {
        let end: Date
        switch state {
        case .beforeSchool(let first) where isLeadIn: end = first.start
        case .inBlock(let current, _): end = current.end
        case .passing(_, let next, _): end = next.start
        default: return nil
        }
        return date...max(date, end)
    }

    public var focus: ResolvedBlock? {
        let span: ResolvedSpan
        switch state {
        case .beforeSchool(let first): span = first
        case .inBlock(let current, _): span = current
        case .passing(_, let next, _): span = next
        default: return nil
        }
        return timeline.blocks.first { span.blockIDs.contains($0.id) }
    }

    public var upcoming: ResolvedBlock? {
        guard let focus, let index = timeline.blocks.firstIndex(where: { $0.id == focus.id }),
              index + 1 < timeline.blocks.count else { return nil }
        return timeline.blocks[index + 1]
    }
}

public struct WidgetSchedulePlan: Sendable {
    public let entries: [WidgetScheduleEntry]
    public let reloadAfter: Date
}

public enum WidgetTimelinePlanner {
    public static let kind = "ScheduleWidget"
    public static let homeURL = URL(string: "stevenson-space://home/today")!

    public static func isHomeURL(_ url: URL) -> Bool {
        url.scheme == homeURL.scheme && url.host == "home" && url.path == "/today"
    }

    /// Seven school-calendar dates, starting today. No network, storage, clock,
    /// WidgetKit, or per-second entries. Midnight refresh is a request, with the
    /// remaining days available if the OS defers it. Search beyond that horizon
    /// for the next school day (e.g. winter/summer break), up to the app's 450-day
    /// bound. Asynchronous days have no bells and are never countdown targets.
    public static func plan(from now: Date, inputs: ResolverInputs) -> WidgetSchedulePlan {
        let today = DayKey(date: now)
        let reloadAfter = today.advanced(by: 1).date()!
        let horizon = today.advanced(by: 7).date()!
        var days: [DayKey: DayTimeline] = [:]
        func timeline(_ day: DayKey) -> DayTimeline {
            if let cached = days[day] { return cached }
            let resolved = resolveDay(day, inputs: inputs, freePeriodGrouping: .separate)
            days[day] = resolved
            return resolved
        }
        var nextDays: [DayKey: DayTimeline] = [:]
        var boundaries: Set<Date> = [now]
        for offset in 0..<7 {
            let day = today.advanced(by: offset)
            let resolved = timeline(day)
            boundaries.insert(day.date()!)
            if let first = resolved.firstBell {
                boundaries.insert(first.addingTimeInterval(-15 * 60))
            }
            for span in resolved.moments {
                boundaries.insert(span.start)
                boundaries.insert(span.end)
            }
            if let last = resolved.lastBell {
                boundaries.insert(last.addingTimeInterval(5 * 60))
            }
            for distance in 1...450 {
                let next = timeline(day.advanced(by: distance))
                if next.isSchoolDay, next.firstBell != nil {
                    nextDays[day] = next
                    break
                }
            }
        }
        let entries = boundaries.filter { $0 >= now && $0 < horizon }.sorted().map { date in
            let day = DayKey(date: date)
            let resolved = timeline(day)
            return WidgetScheduleEntry(date: date, timeline: resolved,
                                       state: momentState(at: date, in: resolved),
                                       nextSchoolDay: nextDays[day])
        }
        return WidgetSchedulePlan(entries: entries, reloadAfter: reloadAfter)
    }
}
