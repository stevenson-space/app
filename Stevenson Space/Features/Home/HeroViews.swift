import SwiftUI
import ScheduleKit

/// Zone 2 — what is happening right now. One layout for every live state, so
/// at a bell the countdown rolls to its new target instead of being replaced:
/// an eyebrow (where), the varsity countdown (how long), a lead line (what),
/// a seam (how far through) and a meta line (what's next).
struct HeroSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.jacketGround) private var ground
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 96.0

    let timeline: DayTimeline
    var isCompact = false

    var body: some View {
        if case .afterSchool = model.currentState {
            if isCompact {
                compactStrip {
                    Label("Done for today", systemImage: "checkmark")
                        .font(.headline)
                        .foregroundStyle(ground.ink)
                }
            } else {
                AfterSchoolHero(next: model.nextSchoolDay, today: model.today,
                                lastBell: timeline.lastBell, pref: model.config.timeFormat)
            }
        } else if let moment = Moment(state: model.currentState, timeline: timeline,
                                      pref: model.config.timeFormat) {
            TimelineView(.animation(minimumInterval: 1.0)) { context in
                let now = context.date.addingTimeInterval(model.displayOffset)
                let remaining = max(moment.target.timeIntervalSince(now), 0)
                let total = max(moment.target.timeIntervalSince(moment.start), 1)
                let fraction = 1 - remaining / total
                Group {
                    if isCompact {
                        compact(moment, remaining: remaining, fraction: fraction)
                    } else {
                        expanded(moment, remaining: remaining, fraction: fraction)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(TimeDisplay.spokenDuration(remaining)) \(moment.spokenSummary)")
            }
        }
    }

    // MARK: Expanded

    private func expanded(_ moment: Moment, remaining: TimeInterval, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(moment.eyebrow)
                .jacketLabel()
                .foregroundStyle(ground.live)

            Text(TimeDisplay.countdown(remaining))
                .font(.varsity(size: heroSize))
                .tracking(-heroSize * 0.035)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(ground.heroFace)
                .twill(ground.heroEdge, x: heroSize / 32, y: heroSize / 24)
                .contentTransition(.numericText(countsDown: true))
                .padding(.leading, -4)
                .padding(.top, 10)

            switch moment.lead {
            case .line(let text):
                Text(text)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ground.ink)
                    .padding(.top, 12)
            case .destination(let text):
                Text(text)
                    .font(.varsity(.largeTitle))
                    .foregroundStyle(ground.ink)
                    .padding(.top, 14)
            }

            Seam(fraction: fraction, on: ground.seamOn, off: ground.seamOff)
                .padding(.top, 22)

            meta(moment)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func meta(_ moment: Moment) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                metaText(moment.metaLeading)
                Spacer(minLength: 12)
                if let trailing = moment.metaTrailing { metaText(trailing) }
            }
            VStack(alignment: .leading, spacing: 4) {
                metaText(moment.metaLeading)
                if let trailing = moment.metaTrailing { metaText(trailing) }
            }
        }
        .font(.subheadline)
        .foregroundStyle(ground.ink2)
    }

    /// Values in the meta line are strongly emphasized and take the main ink.
    private func metaText(_ text: AttributedString) -> some View {
        var styled = text
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            styled[run.range].foregroundColor = ground.ink
        }
        return Text(styled)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Compact

    private func compact(_ moment: Moment, remaining: TimeInterval, fraction: Double) -> some View {
        compactStrip {
            HStack(spacing: 12) {
                Text(TimeDisplay.countdown(remaining))
                    .font(.varsity(.title2))
                    .monospacedDigit()
                    .foregroundStyle(ground.heroFace)
                    .twill(ground.heroEdge, x: 1.5, y: 2)
                    .contentTransition(.numericText(countsDown: true))
                Text(moment.compactLabel)
                    .font(.subheadline)
                    .foregroundStyle(ground.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Seam(fraction: fraction, on: ground.seamOn, off: ground.seamOff,
                     stitches: 12, height: 3, spacing: 2)
                    .frame(width: 54)
            }
        }
    }

    private func compactStrip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .floatingGlass(in: Capsule())
    }
}

/// The words around the countdown for one live state.
private struct Moment {
    enum Lead {
        /// "left in AP Physics C"
        case line(String)
        /// "to Room 1311" — between bells the room is what matters.
        case destination(String)
    }

    let start: Date
    let target: Date
    let eyebrow: String
    let lead: Lead
    let metaLeading: AttributedString
    let metaTrailing: AttributedString?
    let compactLabel: String
    let spokenSummary: String

    init?(state: MomentState, timeline: DayTimeline, pref: TimeFormatPref) {
        func time(_ date: Date) -> String { TimeDisplay.time(date, pref) }
        /// Plain text with the values (`strong`) emphasized. Built by hand, not
        /// from Markdown, because class names are typed by the student.
        func meta(_ parts: (String, Bool)...) -> AttributedString {
            parts.reduce(into: AttributedString()) { result, part in
                var segment = AttributedString(part.0)
                if part.1 { segment.inlinePresentationIntent = .stronglyEmphasized }
                result += segment
            }
        }

        switch state {
        case .beforeSchool(let first):
            start = first.start.addingTimeInterval(-3600)
            target = first.start
            eyebrow = "Before school"
            lead = .line("until the first bell")
            metaLeading = meta((first.displayName, true), (" at ", false), (time(first.start), true))
            metaTrailing = first.room.map { meta(("Room ", false), ($0, true)) }
            compactLabel = "until the first bell"
            spokenSummary = "until the first bell, \(first.displayName) at \(time(first.start))"

        case .inBlock(let current, let next):
            start = current.start
            target = current.end
            let period = timeline.periodLabel(for: current)
            let place = [period.map { "Period \($0)" }, current.room.map { "Room \($0)" }]
                .compactMap { $0 }
            eyebrow = place.isEmpty ? timeline.scheduleLabel : place.joined(separator: " · ")
            switch current.role {
            case .free:
                lead = .line("free until \(time(current.end))")
                compactLabel = "free"
            default:
                lead = .line("left in \(current.displayName)")
                compactLabel = "left in \(current.displayName)"
            }
            metaLeading = meta(("Ends ", false), (time(current.end), true))
            if let next {
                metaTrailing = meta(("Next: ", false), (next.displayName, true), (" at ", false), (time(next.start), true))
            } else {
                metaTrailing = AttributedString(current.role == .free
                    ? "Free for the rest of the day" : "Last block of the day")
            }
            spokenSummary = "\(compactLabel). " + [period.map { "Period \($0)" }, current.room.map { "room \($0)" }]
                .compactMap { $0 }.joined(separator: ", ")
                + (next.map { ". Next: \($0.displayName) at \(time($0.start))" } ?? "")

        case .passing(let from, let to, let kind):
            start = from.end
            target = to.start
            let fromLabel = timeline.periodLabel(for: from)
            let toLabel = timeline.periodLabel(for: to)
            let route = (fromLabel != nil && toLabel != nil) ? " · \(fromLabel!) → \(toLabel!)" : ""
            eyebrow = (kind == .intraPeriod ? "Switching halves" : "Passing period") + route
            if let room = to.room {
                lead = .destination("to Room \(room)")
                metaLeading = meta((to.displayName, true), (" starts at ", false), (time(to.start), true))
            } else {
                lead = .destination("to \(to.displayName)")
                metaLeading = meta(("Starts at ", false), (time(to.start), true))
            }
            metaTrailing = nil
            compactLabel = "to " + (to.room.map { "Room \($0)" } ?? to.displayName)
            spokenSummary = "until \(to.displayName)"
                + (to.room.map { " in room \($0)" } ?? "") + " at \(time(to.start))"

        default:
            return nil
        }
    }
}

/// After the last bell: done for today, then the next school day.
struct AfterSchoolHero: View {
    @Environment(\.jacketGround) private var ground

    let next: DayTimeline?
    let today: DayKey
    let lastBell: Date?
    let pref: TimeFormatPref

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Done for today")
                .font(.varsity(.largeTitle))
                .foregroundStyle(ground.ink)
                .accessibilityAddTraits(.isHeader)
            if let lastBell {
                Text("The last bell rang at \(TimeDisplay.time(lastBell, pref)).")
                    .font(.subheadline)
                    .foregroundStyle(ground.ink2)
                    .padding(.top, 8)
            }
            if let next {
                NextSchoolDayBlock(next: next, today: today, pref: pref)
                    .padding(.top, 56)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The next school day: when it is, whether it's special, and its first bell
/// as the hero. Used after school and on every no-school screen.
struct NextSchoolDayBlock: View {
    @Environment(\.jacketGround) private var ground
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 96.0

    let next: DayTimeline
    let today: DayKey
    var pref: TimeFormatPref = .system

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    dayLabel
                    Spacer(minLength: 12)
                    patch
                }
                VStack(alignment: .leading, spacing: 10) {
                    dayLabel
                    patch
                }
            }

            if next.kind == .asynchronous {
                Text("E-Learning Day")
                    .font(.varsity(.largeTitle))
                    .foregroundStyle(ground.ink)
                    .padding(.top, 14)
                Text("No bell schedule. Classwork is online.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ground.ink)
                    .padding(.top, 10)
            } else if let firstBell = next.firstBell {
                BellTimeText(date: firstBell, pref: pref, size: heroSize,
                             face: ground.heroFace, edge: ground.heroEdge)
                    .padding(.leading, -4)
                    .padding(.top, 14)
                Text("First bell")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ground.ink)
                    .padding(.top, 10)
            }

            if let note = next.dayNote {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(ground.ink2)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var dayLabel: some View {
        Text("Next school day · \(TimeDisplay.dayLabel(next.day, relativeTo: today))")
            .jacketLabel()
            .foregroundStyle(ground.ink2)
    }

    @ViewBuilder private var patch: some View {
        if next.kind != .asynchronous && !next.isStandardSchedule {
            JacketPatch(next.scheduleLabel, systemImage: ScheduleStyle.icon(for: next.family))
        }
    }
}
