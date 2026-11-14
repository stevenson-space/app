import SwiftUI
import ScheduleKit

/// Self-ticking countdown digits. Manual rendering (rather than
/// `Text(timerInterval:)`) so DEBUG time travel shifts it too.
struct TickingCountdown: View {
    let target: Date
    let offset: TimeInterval
    var size: CGFloat = 44
    var tint: Color = .primary

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0)) { context in
            let now = context.date.addingTimeInterval(offset)
            Text(TimeDisplay.countdown(target.timeIntervalSince(now)))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText(countsDown: true))
        }
    }
}

/// Sizes the dial and the pill share, since the collapse moves one onto the other.
private enum HeroMetrics {
    static let dialSize: CGFloat = 270
    static let dialRingWidth: CGFloat = 16
    static let pillRingSize: CGFloat = 36
    static let pillRingWidth: CGFloat = 3
    static let pillPadding: CGFloat = 16
}

/// The hero dial: progress ring around ticking digits.
struct CountdownDial: View {
    let start: Date
    let end: Date
    let tint: Color
    let offset: TimeInterval
    let label: String
    var sublabel: String?
    var ringWidth = HeroMetrics.dialRingWidth
    // The collapse fades the label and then the digits out before each shrinks
    // past reading.
    var digitsOpacity = 1.0
    var labelOpacity = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0)) { context in
            let now = context.date.addingTimeInterval(offset)
            let total = max(end.timeIntervalSince(start), 1)
            let fraction = min(max(now.timeIntervalSince(start) / total, 0), 1)
            let remaining = max(end.timeIntervalSince(now), 0)

            ZStack {
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: ringWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 6) {
                    Text(TimeDisplay.countdown(remaining))
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 30)
                        .opacity(digitsOpacity)
                    Text(label)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                        .opacity(labelOpacity)
                }
            }
            .frame(width: HeroMetrics.dialSize, height: HeroMetrics.dialSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TimeDisplay.spokenDuration(remaining)) \(label)")
        }
    }
}

/// Zone 2 — switches presentation per moment state. Passing gets a visibly
/// different layout, not just a different color.
///
/// It always takes the full hero's height and draws the collapsed pill over its
/// top. `collapse` says how far along it is between the two, so whoever lays it
/// out can scrub the collapse; Home ties it to the scroll position.
struct HeroSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 is the full hero and 1 the pill.
    var collapse: CGFloat = 0
    /// Height of the pill, measured here for whoever drives `collapse`.
    @Binding var pillHeight: CGFloat

    @State private var width: CGFloat = 0

    /// When each part leaves or arrives, as fractions of the collapse.
    private enum Phase {
        static let nextLineOut: ClosedRange<CGFloat> = 0...0.25
        static let dialLabelOut: ClosedRange<CGFloat> = 0.2...0.45
        static let dialDigitsOut: ClosedRange<CGFloat> = 0.5...0.75
        static let pillTextIn: ClosedRange<CGFloat> = 0.7...1
        static let pillIconIn: ClosedRange<CGFloat> = 0.75...0.95
        static let pillPlateIn: ClosedRange<CGFloat> = 0.88...1
        // The passing card closes down into the pill's plate and swaps content inside it.
        static let cardTextOut: ClosedRange<CGFloat> = 0.2...0.55
        static let cardPillIn: ClosedRange<CGFloat> = 0.5...0.85
        static let cardPlateSwap: ClosedRange<CGFloat> = 0.7...1
        // "Done for today" has nothing to hand over and swaps for its pill as a whole.
        static let heroOut: ClosedRange<CGFloat> = 0.35...0.7
        static let pillIn: ClosedRange<CGFloat> = 0.6...0.9
        // Reduce Motion: nothing moves, so the hero clears before the list reaches it.
        static let plainHeroOut: ClosedRange<CGFloat> = 0...0.3
        static let plainPillIn: ClosedRange<CGFloat> = 0.3...0.6
    }

    var body: some View {
        let pref = model.config.timeFormat

        // Each size keys its content by span inside its own container, so a bell
        // change cross-fades in place. The collapse effects sit inside that key,
        // so an outgoing hero keeps its own while it fades.
        ZStack(alignment: .top) {
            ZStack {
                compactContent(pref: pref)
                    .id(model.currentSpanID)
                    .transition(spanTransition)
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
            } action: { height in
                pillHeight = height
            }
            .accessibilityHidden(collapse < 0.5)

            // On top, so a dial that has shrunk into the pill's ring sits on its plate.
            ZStack {
                heroContent(pref: pref)
                    .id(model.currentSpanID)
                    .transition(spanTransition)
            }
            .accessibilityHidden(collapse >= 0.5)
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            self.width = width
        }
        .animation(heroAnimation, value: model.currentSpanID)
    }

    @ViewBuilder
    private func heroContent(pref: TimeFormatPref) -> some View {
        switch model.currentState {
        case .beforeSchool(let first):
            dialHero(
                start: first.start.addingTimeInterval(-3600), end: first.start, tint: .blue,
                label: "until school starts", pillIcon: "sunrise.fill"
            ) {
                nextLine(icon: "sunrise", text:
                    "\(first.displayName) starts at \(TimeDisplay.time(first.start, pref))")
            }

        case .inBlock(let current, let next):
            dialHero(
                start: current.start, end: current.end, tint: ScheduleStyle.tint(for: current.role),
                label: heroLabel(for: current, pref: pref), pillIcon: "clock.fill"
            ) {
                if let next {
                    nextLine(icon: "arrow.right", text:
                        "Next: \(next.displayName)\(roomSuffix(next)) at \(TimeDisplay.time(next.start, pref))")
                } else if current.role == .free {
                    nextLine(icon: "checkmark", text: "You're free for the rest of the day")
                } else {
                    nextLine(icon: "checkmark", text: "Last block of the day")
                }
            }

        case .passing(_, let to, let kind):
            PassingHero(
                to: to, kind: kind, offset: model.displayOffset, pref: pref,
                squeeze: motion, pillHeight: pillHeight,
                contentOpacity: 1 - ramp(reduceMotion ? Phase.plainHeroOut : Phase.cardTextOut),
                plateOpacity: 1 - ramp(reduceMotion ? Phase.plainHeroOut : Phase.cardPlateSwap))

        case .afterSchool:
            AfterSchoolHero(next: model.nextSchoolDay, today: model.today, pref: pref)
                .shrinking(toHeight: pillHeight, progress: motion)
                .opacity(1 - ramp(reduceMotion ? Phase.plainHeroOut : Phase.heroOut))

        default:
            // Non-school day kinds never reach the hero; HomeView routes them
            // to full-screen status views.
            EmptyView()
        }
    }

    @ViewBuilder
    private func compactContent(pref: TimeFormatPref) -> some View {
        switch model.currentState {
        case .beforeSchool(let first):
            dialPill(CountdownPill(
                target: first.start, label: "until school starts", tint: .blue,
                start: first.start.addingTimeInterval(-3600), icon: "sunrise.fill",
                offset: model.displayOffset))
        case .inBlock(let current, _):
            dialPill(CountdownPill(
                target: current.end, label: heroLabel(for: current, pref: pref),
                tint: ScheduleStyle.tint(for: current.role), start: current.start,
                offset: model.displayOffset))
        case .passing(_, let to, let kind):
            passingPill(CountdownPill(
                target: to.start,
                label: "\(kind == .intraPeriod ? "Switching halves" : "Passing") · \(to.displayName)\(roomSuffix(to))",
                tint: .orange, icon: "figure.walk", offset: model.displayOffset))
        case .afterSchool:
            Label("Done for today", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
                .opacity(pillOpacity)
        default:
            EmptyView()
        }
    }

    /// The dial and the line under it. As the hero collapses the line fades, and
    /// the dial shrinks onto the pill's ring slot and stays there as its ring.
    private func dialHero(start: Date, end: Date, tint: Color, label: String, pillIcon: String,
                          @ViewBuilder nextLine: () -> some View) -> some View {
        let morph = dialMorph

        return VStack(spacing: 14) {
            CountdownDial(
                start: start, end: end, tint: tint, offset: model.displayOffset, label: label,
                ringWidth: morph.ringWidth,
                digitsOpacity: reduceMotion ? 1 : 1 - ramp(Phase.dialDigitsOut),
                labelOpacity: reduceMotion ? 1 : 1 - ramp(Phase.dialLabelOut))
                .overlay {
                    // The pill's icon, held at its own size inside the shrinking ring.
                    Image(systemName: pillIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .scaleEffect(1 / morph.scale)
                        .opacity(reduceMotion ? 0 : ramp(Phase.pillIconIn))
                        .accessibilityHidden(true)
                }
                .scaleEffect(morph.scale, anchor: .top)
                .offset(morph.offset)
            nextLine()
                .opacity(reduceMotion ? 1 : 1 - ramp(Phase.nextLineOut))
        }
        .opacity(reduceMotion ? 1 - ramp(Phase.plainHeroOut) : 1)
    }

    /// The pill a dial collapses into. The dial arrives as its ring, so the pill
    /// leaves its own out and brings the text in beside the dial.
    private func dialPill(_ pill: CountdownPill) -> some View {
        var pill = pill
        if !reduceMotion {
            pill.ringOpacity = 0
            pill.plateOpacity = ramp(Phase.pillPlateIn)
            pill.textOpacity = ramp(Phase.pillTextIn)
            pill.textOffset = dialMorph.textOffset
        }
        return pill.opacity(reduceMotion ? pillOpacity : 1)
    }

    /// The pill the passing card closes down into: its ring and text come in
    /// once the card's own have gone, and its plate takes over from the card's.
    private func passingPill(_ pill: CountdownPill) -> some View {
        var pill = pill
        if !reduceMotion {
            pill.ringOpacity = ramp(Phase.cardPillIn)
            pill.textOpacity = ramp(Phase.cardPillIn)
            pill.plateOpacity = ramp(Phase.cardPlateSwap)
        }
        return pill.opacity(reduceMotion ? pillOpacity : 1)
    }

    /// Progress of everything that moves or resizes; Reduce Motion keeps to fades.
    private var motion: CGFloat {
        reduceMotion ? 0 : collapse
    }

    private var dialMorph: DialMorph {
        DialMorph(progress: motion, heroWidth: width, pillHeight: pillHeight)
    }

    private var pillOpacity: Double {
        ramp(reduceMotion ? Phase.plainPillIn : Phase.pillIn)
    }

    /// 0 before `phase`, 1 after it, linear across it.
    private func ramp(_ phase: ClosedRange<CGFloat>) -> Double {
        let span = phase.upperBound - phase.lowerBound
        return Double(min(max((collapse - phase.lowerBound) / span, 0), 1))
    }

    /// A bell change cross-fades in place. Once the hero has pinned and begun to
    /// collapse, the outgoing one drops out at once, which would leave the new
    /// one fading in over an empty header, so there the two swap outright.
    private var spanTransition: AnyTransition {
        collapse > 0 ? .identity : .opacity
    }

    private var heroTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.94))
                .combined(with: .offset(y: 18)),
            removal: .opacity
                .combined(with: .scale(scale: 1.03))
                .combined(with: .offset(y: -10))
        )
    }

    private var heroAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.52, dampingFraction: 0.8)
    }

    private func heroLabel(for span: ResolvedSpan, pref: TimeFormatPref) -> String {
        switch span.role {
        case .free:
            return "free — until \(TimeDisplay.time(span.end, pref))"
        case .lunch:
            return "left in Lunch"
        case .advisory:
            return "left in Advisory"
        default:
            return "left in \(span.displayName)"
        }
    }

    private func roomSuffix(_ span: ResolvedSpan) -> String {
        span.room.map { " · Rm \($0)" } ?? ""
    }

    private func nextLine(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// Where the dial is part-way through the collapse. It scales from its place at
/// the top centre of the hero down to the pill's ring slot.
private struct DialMorph {
    /// 0 is the dial and 1 the pill's ring.
    let progress: CGFloat
    let heroWidth: CGFloat
    let pillHeight: CGFloat

    private var diameter: CGFloat {
        HeroMetrics.dialSize + (HeroMetrics.pillRingSize - HeroMetrics.dialSize) * progress
    }

    var scale: CGFloat {
        diameter / HeroMetrics.dialSize
    }

    /// Stroke to draw at, so that once scaled it runs from the dial's to the pill's.
    var ringWidth: CGFloat {
        let scaled = HeroMetrics.dialRingWidth
            + (HeroMetrics.pillRingWidth - HeroMetrics.dialRingWidth) * progress
        return scaled / scale
    }

    /// Centre of the ring slot, from the pill's leading edge.
    private var slotCenterX: CGFloat {
        HeroMetrics.pillPadding + HeroMetrics.pillRingSize / 2
    }

    /// How far the dial has moved toward the slot. Squared across, so it shrinks
    /// in place while it is large and tucks into the corner late.
    var offset: CGSize {
        CGSize(width: progress * progress * (slotCenterX - heroWidth / 2),
               height: progress * (pillHeight - HeroMetrics.pillRingSize) / 2)
    }

    /// Keeps the pill's text beside the dial while it is still larger than the slot.
    var textOffset: CGSize {
        CGSize(width: offset.width + heroWidth / 2 - slotCenterX
                   + (diameter - HeroMetrics.pillRingSize) / 2,
               height: offset.height + (diameter - pillHeight) / 2)
    }
}

/// The collapsed countdown: ring, digits and label on one plate.
private struct CountdownPill: View {
    let target: Date
    let label: String
    let tint: Color
    var start: Date?
    var icon = "clock.fill"
    let offset: TimeInterval
    // The collapse brings the parts in separately. A dial collapsing into the
    // pill stands in for the ring, so that stays hidden.
    var ringOpacity = 1.0
    var plateOpacity = 1.0
    var textOpacity = 1.0
    var textOffset = CGSize.zero

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0)) { context in
            let remaining = max(target.timeIntervalSince(context.date.addingTimeInterval(offset)), 0)
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(tint.opacity(0.16), lineWidth: HeroMetrics.pillRingWidth)
                    if let start {
                        let duration = max(target.timeIntervalSince(start), 1)
                        Circle()
                            .trim(from: 0, to: min(max(1 - remaining / duration, 0), 1))
                            .stroke(tint.gradient, style: StrokeStyle(lineWidth: HeroMetrics.pillRingWidth,
                                                                      lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: HeroMetrics.pillRingSize, height: HeroMetrics.pillRingSize)
                .opacity(ringOpacity)
                .accessibilityHidden(true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        digits(remaining)
                        Text(label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        digits(remaining)
                        Text(label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(textOpacity)
                .offset(textOffset)
            }
            .padding(.horizontal, HeroMetrics.pillPadding)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(LinearGradient(colors: [tint.opacity(0.12), tint.opacity(0.025)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(tint.opacity(0.18), lineWidth: 0.75)
                    }
                    .shadow(color: tint.opacity(0.08), radius: 10, y: 4)
                    .opacity(plateOpacity)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TimeDisplay.spokenDuration(remaining)) \(label)")
        }
    }

    private func digits(_ remaining: TimeInterval) -> some View {
        Text(TimeDisplay.countdown(remaining))
            .font(.system(.title2, design: .rounded, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .contentTransition(.numericText(countsDown: true))
    }
}

private extension View {
    /// Scales the view toward its top, so its height runs from its own to
    /// `height` as `progress` goes from 0 to 1.
    func shrinking(toHeight height: CGFloat, progress: CGFloat) -> some View {
        visualEffect { content, geometry in
            let fit = geometry.size.height > 0 ? height / geometry.size.height : 1
            return content.scaleEffect(1 + (fit - 1) * progress, anchor: .top)
        }
    }
}

/// Passing period: banner card, walking icon, countdown to the next block.
/// Deliberately unlike the class dial — a two-second glance must distinguish
/// "keep walking" from "sit down".
struct PassingHero: View {
    let to: ResolvedSpan
    let kind: PassingKind
    let offset: TimeInterval
    let pref: TimeFormatPref
    /// Toward 1 the plate closes down to `pillHeight`, at full width, with the
    /// content shrinking inside it.
    var squeeze: CGFloat = 0
    var pillHeight: CGFloat = 0
    var contentOpacity = 1.0
    var plateOpacity = 1.0

    var body: some View {
        VStack(spacing: 10) {
            Label(kind == .intraPeriod ? "Switching Halves" : "Passing Period",
                  systemImage: "figure.walk")
                .font(.headline)
                .foregroundStyle(.orange)
                .textCase(.uppercase)

            TickingCountdown(target: to.start, offset: offset, size: 46, tint: .orange)

            Text("\(to.displayName)\(to.room.map { " · Rm \($0)" } ?? "") starts at \(TimeDisplay.time(to.start, pref))")
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .shrinking(toHeight: pillHeight, progress: squeeze)
        .opacity(contentOpacity)
        .background {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1.5)
                    .frame(height: geometry.size.height + (pillHeight - geometry.size.height) * squeeze)
            }
            .opacity(plateOpacity)
        }
        .accessibilityElement(children: .combine)
    }
}

/// After the last bell: done for today, plus what tomorrow looks like.
struct AfterSchoolHero: View {
    let next: DayTimeline?
    let today: DayKey
    let pref: TimeFormatPref

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Done for today")
                .font(.title2.bold())
            if let next {
                NextSchoolDayCard(next: next, today: today, pref: pref)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// "Tomorrow: Late Arrival" — used by after-school, weekend, break screens.
struct NextSchoolDayCard: View {
    let next: DayTimeline
    let today: DayKey
    var pref: TimeFormatPref = .system

    var body: some View {
        let accent = ScheduleStyle.accent(for: next.family)
        HStack(spacing: 10) {
            Image(systemName: next.kind == .asynchronous
                  ? "laptopcomputer" : ScheduleStyle.icon(for: next.family))
                .foregroundStyle(next.kind == .asynchronous ? .blue : accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(TimeDisplay.dayLabel(next.day, relativeTo: today))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(next.scheduleLabel)
                    .font(.subheadline.weight(.semibold))
                if let note = next.dayNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let firstBell = next.firstBell {
                Text(TimeDisplay.time(firstBell, pref))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 24)
    }
}
