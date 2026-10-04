import Foundation
import ScheduleKit

/// Read the same persisted inputs as widgets, without constructing another
/// AppModel, touching student identity, or starting UI timers and sync tasks.
struct IntentScheduleContext {
    let inputs: ResolverInputs
    let cachedMenu: Data?
    let now: Date

    init(now: Date = Date()) throws {
        do {
            let snapshot = try SharedStore.readLunchWidgetData()
            inputs = snapshot.schedule.resolverInputs(catalog: try BellScheduleCatalog.loadBundled())
            cachedMenu = snapshot.cachedMenu
            #if DEBUG
            self.now = snapshot.schedule.widgetClock.scheduleDate(for: now)
            #else
            self.now = now
            #endif
        } catch {
            throw IntentDataError.unavailable
        }
    }

    var inquiry: ScheduleInquiry { ScheduleInquiry(at: now, inputs: inputs) }

    func timeline(on date: Date?) -> DayTimeline {
        resolveDay(DayKey(date: date ?? now), inputs: inputs)
    }

    func summary(_ block: ResolvedBlock) -> String {
        let period = block.spanLabel.map { "Period \($0)" } ?? block.periodID.defaultDisplayName
        let name = block.displayName == period ? period : "\(block.displayName), \(period)"
        let room = block.room.map { ", room \($0)" } ?? ""
        return "\(name)\(room), from \(TimeDisplay.time(block.start, inputs.config.timeFormat)) to \(TimeDisplay.time(block.end, inputs.config.timeFormat))."
    }

    func status(_ inquiry: ScheduleInquiry) -> String {
        switch inquiry.state {
        case .beforeSchool: return "School hasn't started yet."
        case .afterSchool: return "School is over for today."
        case .passing(_, let next, _): return "It's passing time before \(next.displayName)."
        case .inBlock(let current, _): return "It's \(current.displayName) right now."
        case .asynchronous: return "Today is an asynchronous learning day."
        case .unknownSchedule: return "Today's schedule is unavailable."
        case .weekend, .breakDay, .noSchool, .outsideYear:
            return "No scheduled classes today. \(inquiry.timeline.scheduleLabel)."
        }
    }

    func scheduleSummary(_ timeline: DayTimeline) -> String {
        var text = "\(TimeDisplay.shortDayLabel(timeline.day)): \(timeline.scheduleLabel)."
        if let note = timeline.dayNote { text += " \(note)." }
        if timeline.rotationUncertain { text += " The finals rotation is unconfirmed; check the schedule in the app." }
        return text
    }

    func qualifying(_ answer: String, for timeline: DayTimeline) -> String {
        guard timeline.rotationUncertain else { return answer }
        return "\(answer) The finals rotation is unconfirmed; check the schedule in the app."
    }
}

private enum IntentDataError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Unlock your iPhone and open Stevenson Space once to make your saved schedule available, then try again."
    }
}
