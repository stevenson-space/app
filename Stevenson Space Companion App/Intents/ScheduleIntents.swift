import AppIntents
import Foundation
import ScheduleKit
import SwiftUI

struct GetCurrentClassIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Class"
    static let description = IntentDescription(
        "Get the academic class happening now, including its period, saved room, and times. Uses your saved schedule. Lunch, free periods, and events aren't academic classes.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<ScheduleBlockEntity?> & ProvidesDialog {
        let context = try IntentScheduleContext()
        let inquiry = context.inquiry
        let text = inquiry.currentClass.map { context.summary($0) } ?? context.status(inquiry)
        return .result(value: inquiry.currentClass.map(ScheduleBlockEntity.init),
                       dialog: "\(context.qualifying(text, for: inquiry.timeline))")
    }
}

struct GetCurrentPeriodIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Period"
    static let description = IntentDescription(
        "Get the schedule block happening now, including lunch, advisory, and free periods. Returns its period, name, saved room, and times. Uses your saved schedule.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<ScheduleBlockEntity?> & ProvidesDialog {
        let context = try IntentScheduleContext()
        let inquiry = context.inquiry
        let text = inquiry.currentPeriod.map { context.summary($0) } ?? context.status(inquiry)
        return .result(value: inquiry.currentPeriod.map(ScheduleBlockEntity.init),
                       dialog: "\(context.qualifying(text, for: inquiry.timeline))")
    }
}

struct GetNextClassIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Next Class"
    static let description = IntentDescription(
        "Get the next academic class starting today, with its period, saved room, and times. Skips lunch, free time, and events. Uses your saved schedule; returns no value when no classes remain today.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<ScheduleBlockEntity?> & ProvidesDialog {
        let context = try IntentScheduleContext()
        let inquiry = context.inquiry
        let text = inquiry.nextClass.map { "Next is \(context.summary($0))" }
            ?? "There are no more scheduled classes starting today."
        return .result(value: inquiry.nextClass.map(ScheduleBlockEntity.init),
                       dialog: "\(context.qualifying(text, for: inquiry.timeline))")
    }
}

struct GetScheduleIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Schedule"
    static let description = IntentDescription(
        "Get all schedule blocks for a date, including names, periods, saved rooms, and start/end times. Leave Date empty for today. Uses your saved calendar and overrides; all dates follow Chicago time.")

    @Parameter(title: "Date") var date: Date?
    static var parameterSummary: some ParameterSummary {
        Summary("Get schedule for \(\.$date)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[ScheduleBlockEntity]> & ProvidesDialog & ShowsSnippetView {
        let context = try IntentScheduleContext()
        let timeline = context.timeline(on: date)
        let heading = context.scheduleSummary(timeline)
        let details = timeline.blocks.map { context.summary($0) }.joined(separator: "\n")
        let dialog = timeline.blocks.isEmpty ? "\(heading) There are no timed periods."
            : "\(heading) There are \(timeline.blocks.count) schedule blocks, from \(TimeDisplay.time(timeline.blocks[0].start, .twelveHour)) to \(TimeDisplay.time(timeline.blocks[timeline.blocks.count - 1].end, .twelveHour))."
        return .result(value: timeline.blocks.map(ScheduleBlockEntity.init), dialog: "\(dialog)") {
            IntentTextSnippet(title: heading, detail: details.isEmpty ? "No timed periods." : details)
        }
    }
}

struct GetScheduleTypeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Schedule Type"
    static let description = IntentDescription(
        "Get the schedule type for a date, such as Standard, Late Arrival, or No School. Leave Date empty for today. Uses your saved calendar and overrides in Chicago time.")

    @Parameter(title: "Date") var date: Date?
    static var parameterSummary: some ParameterSummary {
        Summary("Get schedule type for \(\.$date)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = try IntentScheduleContext()
        let timeline = context.timeline(on: date)
        return .result(value: timeline.scheduleLabel, dialog: "\(context.scheduleSummary(timeline))")
    }
}

struct GetLunchMenuIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Lunch Menu"
    static let description = IntentDescription(
        "Get all lunch stations for a date as text. Leave Date empty for today. Uses the saved or bundled menu and school calendar in Chicago time. Returns no value when lunch isn't served or the menu is unavailable.")

    @Parameter(title: "Date") var date: Date?
    static var parameterSummary: some ParameterSummary {
        Summary("Get lunch menu for \(\.$date)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> & ProvidesDialog & ShowsSnippetView {
        let context = try IntentScheduleContext()
        let timeline = context.timeline(on: date)
        let menu = LunchMenuLoader.load(cachedData: context.cachedMenu, on: timeline.day)
        let lunch = LunchMenuLoader.menu(menu, for: timeline.day, inputs: context.inputs)
        let heading = "Lunch for \(TimeDisplay.shortDayLabel(timeline.day))"
        let text = lunch.map { day in
            day.sections.map { "\($0.station.title): \($0.items.joined(separator: ", "))" }
                .joined(separator: "\n")
        }
        let unavailable = timeline.isSchoolDay && timeline.family != .summer
            ? "The lunch menu is unavailable for this date."
            : "Lunch isn't served on this date."
        let detail = text ?? unavailable
        return .result(value: text, dialog: "\(heading). \(detail)") {
            IntentTextSnippet(title: heading, detail: detail)
        }
    }
}

private struct IntentTextSnippet: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(detail).font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
