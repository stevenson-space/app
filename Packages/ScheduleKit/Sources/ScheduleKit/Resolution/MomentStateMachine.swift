import Foundation

/// The instantaneous answer to "what is happening right now". Pure function of
/// a timestamp and a resolved day — every surface (app, future widgets, future
/// Live Activity) calls exactly this.
///
/// Intervals are half-open [start, end): at the exact second a block ends, the
/// next state has begun. Zero-length gaps (Early Dismissal's Makeup starts the
/// second period 4/8 ends) produce no passing state at all — no instant exists
/// inside an empty interval.
public func momentState(at now: Date, in timeline: DayTimeline) -> MomentState {
    switch timeline.kind {
    case .weekend: return .weekend
    case .breakDay(let label): return .breakDay(label: label)
    case .noSchool: return .noSchool
    case .asynchronous: return .asynchronous
    case .outsideYear: return .outsideYear
    case .unknownType(let name): return .unknownSchedule(name: name)
    case .school: break
    }

    let spans = timeline.moments
    guard let first = spans.first, let last = spans.last else {
        // A school day with zero blocks would be a data bug; stay honest.
        return .unknownSchedule(name: timeline.scheduleLabel)
    }

    if now < first.start { return .beforeSchool(first: first) }
    if now >= last.end { return .afterSchool }

    for (index, span) in spans.enumerated() {
        if now >= span.start && now < span.end {
            let next = index + 1 < spans.count ? spans[index + 1] : nil
            return .inBlock(current: span, next: next)
        }
        if index + 1 < spans.count {
            let next = spans[index + 1]
            if now >= span.end && now < next.start {
                let kind: PassingKind =
                    (span.periodID != nil && span.periodID == next.periodID)
                    ? .intraPeriod : .betweenPeriods
                return .passing(from: span, to: next, kind: kind)
            }
        }
    }

    return .afterSchool
}
