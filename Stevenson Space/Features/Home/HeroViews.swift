import SwiftUI
import ScheduleKit

/// Zone 2 — what is happening right now. One layout for every live state, so
/// at a bell the countdown rolls to its new target instead of being replaced:
/// an eyebrow (where), the varsity countdown (how long), a lead line (what),
/// a seam (how far through) and a meta line (what's next).
///
/// It always takes the full hero's height and draws the collapsed strip over
/// its top. `collapse` says how far along it is between the two, so whoever
/// lays it out can scrub the collapse; Home ties it to the scroll position.
struct HeroSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.jacketGround) private var ground
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 96.0

    let timeline: DayTimeline
    /// 0 is the full hero and 1 the strip.
    var collapse: CGFloat = 0
    /// Height of the strip, measured here for whoever drives `collapse`.
    @Binding var pillHeight: CGFloat

    /// Where the hero's countdown and the strip's sit, so the collapse can
    /// shrink one onto the other.
    @State private var heroDigitsFrame: CGRect = .zero
    @State private var stripDigitsFrame: CGRect = .zero

    private static let space = "HeroSection"

    /// When each part leaves or arrives, as fractions of the collapse.
    private enum Phase {
        static let lowerOut: ClosedRange<CGFloat> = 0...0.25
        static let eyebrowOut: ClosedRange<CGFloat> = 0.1...0.35
        static let plateIn: ClosedRange<CGFloat> = 0.75...1
        static let stripTextIn: ClosedRange<CGFloat> = 0.8...1
        // "Done for today" has nothing to hand over and swaps for its strip as a whole.
        static let heroOut: ClosedRange<CGFloat> = 0.35...0.7
        static let stripIn: ClosedRange<CGFloat> = 0.6...0.9
        // Reduce Motion: nothing moves, so the hero clears before the list reaches it.
        static let plainHeroOut: ClosedRange<CGFloat> = 0...0.3
        static let plainStripIn: ClosedRange<CGFloat> = 0.3...0.6
    }

    var body: some View {
        Group {
            if case .afterSchool = model.currentState {
                layers {
                    compactStrip(plateOpacity: stripOpacity) {
                        Label("Done for today", systemImage: "checkmark")
                            .font(.headline)
                            .foregroundStyle(ground.ink)
                            .opacity(stripOpacity)
                    }
                } hero: {
                    AfterSchoolHero(next: model.nextSchoolDay, today: model.today,
                                    lastBell: timeline.lastBell, pref: model.config.timeFormat)
                        .shrinking(toHeight: pillHeight, progress: motion)
                        .opacity(1 - ramp(reduceMotion ? Phase.plainHeroOut : Phase.heroOut))
                }
            } else if let moment = Moment(state: model.currentState, timeline: timeline,
                                          pref: model.config.timeFormat) {
                TimelineView(.animation(minimumInterval: 1.0)) { context in
                    let now = context.date.addingTimeInterval(model.displayOffset)
                    let remaining = max(moment.target.timeIntervalSince(now), 0)
                    let total = max(moment.target.timeIntervalSince(moment.start), 1)
                    let fraction = 1 - remaining / total
                    layers {
                        compact(moment, remaining: remaining, fraction: fraction)
                    } hero: {
                        expanded(moment, remaining: remaining, fraction: fraction)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(TimeDisplay.spokenDuration(remaining)) \(moment.spokenSummary)")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .coordinateSpace(.named(Self.space))
    }

    /// The strip under the full hero, top-aligned, each heard only while it is
    /// the one showing.
    private func layers(@ViewBuilder strip: () -> some View,
                        @ViewBuilder hero: () -> some View) -> some View {
        ZStack(alignment: .top) {
            strip()
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    pillHeight = height
                }
                .accessibilityHidden(collapse < 0.5)
            // On top, so the countdown that shrinks into the strip sits on its plate.
            hero()
                .accessibilityHidden(collapse >= 0.5)
        }
    }

    // MARK: Expanded

    private func expanded(_ moment: Moment, remaining: TimeInterval, fraction: Double) -> some View {
        // The parts under the countdown go first: the list takes their space.
        let lowerOpacity = reduceMotion ? 1 : 1 - ramp(Phase.lowerOut)

        return VStack(alignment: .leading, spacing: 0) {
            Text(moment.eyebrow)
                .jacketLabel()
                .foregroundStyle(ground.live)
                .opacity(reduceMotion ? 1 : 1 - ramp(Phase.eyebrowOut))

            heroDigits(remaining)
                .padding(.leading, -4)
                .padding(.top, 10)

            Group {
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
            .opacity(lowerOpacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(reduceMotion ? 1 - ramp(Phase.plainHeroOut) : 1)
    }

    /// The varsity countdown. As the hero collapses it shrinks onto the strip's
    /// countdown and stays there as its digits.
    private func heroDigits(_ remaining: TimeInterval) -> some View {
        let morph = DigitsMorph(progress: motion, from: heroDigitsFrame, to: stripDigitsFrame)

        return Text(TimeDisplay.countdown(remaining))
            .font(.varsity(size: heroSize))
            .tracking(-heroSize * 0.035)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(ground.heroFace)
            .twill(ground.heroEdge, x: heroSize / 32, y: heroSize / 24)
            .contentTransition(.numericText(countsDown: true))
            .scaleEffect(morph.scale, anchor: .topLeading)
            .offset(morph.offset)
            // Measured outside the scale and offset, so this is where it is laid out.
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .named(Self.space))
            } action: { frame in
                heroDigitsFrame = frame
            }
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
        let textOpacity = ramp(reduceMotion ? Phase.plainStripIn : Phase.stripTextIn)

        return compactStrip(plateOpacity: ramp(reduceMotion ? Phase.plainStripIn : Phase.plateIn)) {
            HStack(spacing: 12) {
                Text(TimeDisplay.countdown(remaining))
                    .font(.varsity(.title2))
                    .monospacedDigit()
                    .foregroundStyle(ground.heroFace)
                    .twill(ground.heroEdge, x: 1.5, y: 2)
                    .contentTransition(.numericText(countsDown: true))
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .named(Self.space))
                    } action: { frame in
                        stripDigitsFrame = frame
                    }
                    // The hero's countdown arrives in this slot and stands in for
                    // these digits; Reduce Motion fades them in instead.
                    .opacity(reduceMotion ? textOpacity : 0)
                Text(moment.compactLabel)
                    .font(.subheadline)
                    .foregroundStyle(ground.ink)
                    .lineLimit(1)
                    .opacity(textOpacity)
                Spacer(minLength: 4)
                Seam(fraction: fraction, on: ground.seamOn, off: ground.seamOff,
                     stitches: 12, height: 3, spacing: 2)
                    .frame(width: 54)
                    .opacity(textOpacity)
            }
        }
    }

    private func compactStrip<Content: View>(plateOpacity: Double,
                                             @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background {
                Color.clear
                    .floatingGlass(in: Capsule())
                    .opacity(plateOpacity)
            }
    }

    // MARK: Collapse

    /// Progress of everything that moves or resizes; Reduce Motion keeps to fades.
    private var motion: CGFloat {
        reduceMotion ? 0 : collapse
    }

    private var stripOpacity: Double {
        ramp(reduceMotion ? Phase.plainStripIn : Phase.stripIn)
    }

    /// 0 before `phase`, 1 after it, linear across it.
    private func ramp(_ phase: ClosedRange<CGFloat>) -> Double {
        let span = phase.upperBound - phase.lowerBound
        return Double(min(max((collapse - phase.lowerBound) / span, 0), 1))
    }
}

/// Where the hero's countdown is part-way through the collapse: scaled from its
/// top leading corner and moved, from its own place to the strip's countdown.
private struct DigitsMorph {
    let scale: CGFloat
    let offset: CGSize

    init(progress: CGFloat, from hero: CGRect, to strip: CGRect) {
        guard progress > 0, hero.height > 0, strip.height > 0 else {
            scale = 1
            offset = .zero
            return
        }
        scale = 1 + (strip.height / hero.height - 1) * progress
        offset = CGSize(width: (strip.minX - hero.minX) * progress,
                        height: (strip.minY - hero.minY) * progress)
    }
}

private extension View {
    /// Scales the view toward its top leading corner, where the hero's text
    /// starts, so its height runs from its own to `height` as `progress` goes
    /// from 0 to 1.
    func shrinking(toHeight height: CGFloat, progress: CGFloat) -> some View {
        visualEffect { content, geometry in
            let fit = geometry.size.height > 0 ? height / geometry.size.height : 1
            return content.scaleEffect(1 + (fit - 1) * progress, anchor: .topLeading)
        }
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
