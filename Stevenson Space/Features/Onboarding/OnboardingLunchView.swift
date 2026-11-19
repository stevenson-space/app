import SwiftUI
import ScheduleKit

/// Where lunch sits is the one part of a Stevenson schedule that moves the
/// bells: a half-period lunch puts one in the middle of 4th, 5th or 6th. This
/// step asks only that, as times: tap the period, then full or which half,
/// then what fills the half lunch leaves: free, Advisory, or the class next
/// door running a period and a half. Nothing is saved until Continue.
struct OnboardingLunchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let next: () -> Void

    @State private var placement: LunchPlacement?
    @State private var loaded = false
    /// The saved placement the draft was last loaded from or saved as.
    @State private var saved: LunchPlacement?
    /// The question the student answered last. Nil on arrival, so the page
    /// doesn't scroll for a placement that was already there.
    @State private var answered: Question?

    private enum Question: Hashable {
        case period, portion
    }

    var body: some View {
        OnboardingPage(revealing: answered) {
            OnboardingHeading(title: "When’s your lunch?")

            LunchDayStrip(blocks: dayWithDraft, pref: model.config.timeFormat,
                          hasLunch: placement != nil)

            periodPicker

            if let placement {
                portionPicker(placement)
                if let remaining = placement.remainingHalf {
                    otherHalfPicker(placement, remaining: remaining)
                }
            }
        } actions: {
            OnboardingPrimaryButton("Continue") {
                model.updateConfig { $0.setLunchPlacement(placement) }
                saved = model.config.lunchPlacement
                next()
            }
            .disabled(placement == nil)
        }
        .navigationTitle("Step 1 of 3")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { OnboardingProgress(step: 1) }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip", action: next)
            }
        }
        .sensoryFeedback(.selection, trigger: placement?.period)
        .sensoryFeedback(.selection, trigger: placement?.portion)
        .sensoryFeedback(.selection, trigger: placement?.otherHalf)
        .onAppear {
            // The classes step's editor can move lunch while this step is
            // covered. The draft then starts over from what was saved, so
            // Continue can't put the old lunch back. Otherwise a draft is
            // kept, saved or not, as after Skip and Back.
            let current = model.config.lunchPlacement
            guard !loaded || current != saved else { return }
            loaded = true
            saved = current
            placement = current
        }
    }

    // MARK: - Which period

    private var periodPicker: some View {
        tileRow {
            ForEach(Array(UserConfig.advisoryPeriods), id: \.self) { period in
                let option = LunchPlacement(period: period)
                choiceTile(PeriodID.ordinal(period), detail: times(option),
                           accessibilityName: "\(PeriodID.ordinal(period)) period",
                           isSelected: placement?.period == period) {
                    select(.period, startingWith: option) { $0.period = period }
                }
            }
        }
        .id(Question.period)
    }

    // MARK: - How much of it

    /// The whole period or either half, each with the times lunch would run.
    private func portionPicker(_ placement: LunchPlacement) -> some View {
        VStack(spacing: 8) {
            OnboardingSectionLabel("How much of \(PeriodID.ordinal(placement.period)) period?")
            tileRow {
                ForEach([HalfChoice.full, .a, .b], id: \.self) { portion in
                    let name = portion == .full ? "Full" : "\(placement.period)\(portion.rawValue)"
                    choiceTile(name, detail: times(LunchPlacement(period: placement.period, portion: portion)),
                               accessibilityName: portion == .full ? "Full period" : name,
                               isSelected: placement.portion == portion, compact: true) {
                        select(.portion) { $0.portion = portion }
                    }
                }
            }
        }
        .id(Question.portion)
    }

    // MARK: - Tiles

    /// Three across, or stacked where the largest sizes leave too little room
    /// for the times.
    private func tileRow(@ViewBuilder content: () -> some View) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout { content() }
    }

    /// One answer, filled with the accent once chosen, over a line saying what
    /// it means: for lunch, the times it would run.
    private func choiceTile(_ title: String, detail: String, accessibilityName: String,
                            isSelected: Bool, compact: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: compact ? 2 : 4) {
                Text(title)
                    .font(.system(compact ? .headline : .title2, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85))
                                                : AnyShapeStyle(.secondary))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 10 : 14)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(StevensonPalette.accent)
                                     : AnyShapeStyle(Color(.secondarySystemGroupedBackground))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityName), \(detail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - The other half

    /// What fills the half lunch leaves, as a third row of tiles under the
    /// first two, with a line spelling the choice out with its times. The
    /// class next door is offered only while it is there to run long.
    private func otherHalfPicker(_ placement: LunchPlacement, remaining: Half) -> some View {
        let halfName = "\(placement.period)\(remaining.rawValue)"
        var options: [LunchPlacement.OtherHalf] = [.free, .advisory]
        if model.config.neighborClassCanFill(placement) { options.append(.neighborClass) }

        return VStack(spacing: 8) {
            OnboardingSectionLabel("What do you have in \(halfName)?")
            tileRow {
                ForEach(options, id: \.self) { option in
                    let tile = otherHalfTile(option, placement: placement)
                    choiceTile(tile.title, detail: tile.detail, accessibilityName: tile.title,
                               isSelected: placement.otherHalf == option, compact: true) {
                        select(nil) { $0.otherHalf = option }
                    }
                }
            }
            Text(otherHalfSummary(placement, halfName: halfName))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func otherHalfTile(_ option: LunchPlacement.OtherHalf,
                               placement: LunchPlacement) -> (title: String, detail: String) {
        switch option {
        case .free:
            return ("Free", "No class")
        case .advisory:
            return ("Advisory", "Freshmen")
        case .neighborClass:
            let neighbor = placement.neighborPeriod ?? placement.period
            return ("\(PeriodID.ordinal(neighbor)) period",
                    placement.portion == .b ? "Runs long" : "Starts early")
        }
    }

    /// The choice in a sentence, with when the half runs.
    private func otherHalfSummary(_ placement: LunchPlacement, halfName: String) -> String {
        let half = remainingHalfTimes(placement)
        let pref = model.config.timeFormat
        switch placement.otherHalf {
        case .free:
            return half.map { "\(halfName) is a free period, \(TimeDisplay.range($0.start, $0.end, pref))." }
                ?? "\(halfName) is a free period."
        case .advisory:
            return half.map { "Freshmen have Advisory in \(halfName), \(TimeDisplay.range($0.start, $0.end, pref))." }
                ?? "Freshmen have Advisory in \(halfName)."
        case .neighborClass:
            let neighbor = placement.neighborPeriod ?? placement.period
            let ordinal = PeriodID.ordinal(neighbor)
            let name = model.config.customization(for: .period(neighbor))?.name?.nilIfBlank
                .map { "\($0) (\(ordinal) period)" } ?? "\(ordinal) period class"
            guard let half else {
                return "Your \(name) runs a period and a half, through \(halfName)."
            }
            return placement.portion == .b
                ? "Your \(name) runs on through \(halfName), until \(TimeDisplay.time(half.end, pref, includesMeridiem: false))."
                : "Your \(name) starts early, in \(halfName), at \(TimeDisplay.time(half.start, pref, includesMeridiem: false))."
        }
    }

    // MARK: - Helpers

    /// Changes the draft, or starts one, as the answer to `question`. A half
    /// whose neighbour can't run long into it falls back to free rather than
    /// keeping a choice that is gone.
    private func select(_ question: Question?, startingWith initial: LunchPlacement? = nil,
                        _ change: (inout LunchPlacement) -> Void) {
        var updated: LunchPlacement
        if var current = placement {
            change(&current)
            updated = current
        } else if let initial {
            updated = initial
        } else {
            return
        }
        if updated.otherHalf == .neighborClass, !model.config.neighborClassCanFill(updated) {
            updated.otherHalf = .free
        }
        // No animation: the page can't scroll to content that is still growing.
        placement = updated
        if let question { answered = question }
    }

    /// 4th through 6th period of the Standard day as they would run with the
    /// draft, for the strip. Lunch can only fall there, so the rest of the day
    /// is left out to give these periods the room.
    private var dayWithDraft: [ResolvedBlock] {
        var config = model.config
        config.setLunchPlacement(placement)
        let day = standardTemplate(config: config, catalog: model.catalog)
        let lunchPeriods = day.filter {
            $0.periodID.periodNumber.map(UserConfig.advisoryPeriods.contains) ?? false
        }
        guard let start = lunchPeriods.map(\.start).min(),
              let end = lunchPeriods.map(\.end).max() else { return day }
        return day.filter { $0.start >= start && $0.end <= end }
    }

    /// When the half lunch leaves runs, on the Standard schedule.
    private func remainingHalfTimes(_ placement: LunchPlacement) -> (start: Date, end: Date)? {
        guard let remaining = placement.remainingHalf else { return nil }
        var config = UserConfig()
        config.setLunchPlacement(LunchPlacement(period: placement.period, portion: placement.portion))
        let half = standardTemplate(config: config, catalog: model.catalog).first {
            $0.periodID == .period(placement.period) && $0.half == remaining
        }
        return half.map { ($0.start, $0.end) }
    }

    /// When lunch runs for a placement, on the Standard schedule.
    private func times(_ placement: LunchPlacement) -> String {
        var config = UserConfig()
        config.setLunchPlacement(placement)
        let lunch = standardTemplate(config: config, catalog: model.catalog)
            .first { $0.role == .lunch }
        return lunch.map { TimeDisplay.range($0.start, $0.end, model.config.timeFormat) } ?? ""
    }
}

/// The lunch periods of the Standard day as a strip of their blocks, each as
/// wide as it is long, so a choice shows where lunch falls: the period fills,
/// or splits into halves with lunch in one. Before a choice the periods are
/// tinted.
private struct LunchDayStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var height = 58.0

    let blocks: [ResolvedBlock]
    let pref: TimeFormatPref
    let hasLunch: Bool

    private static let spacing: CGFloat = 3

    private var lunch: ResolvedBlock? {
        blocks.first { $0.role == .lunch }
    }

    var body: some View {
        if let first = blocks.first, let last = blocks.last {
            VStack(spacing: 8) {
                GeometryReader { geometry in
                    let total = blocks.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
                    let room = geometry.size.width - Self.spacing * CGFloat(blocks.count - 1)
                    HStack(spacing: Self.spacing) {
                        ForEach(blocks) { block in
                            segment(block)
                                .frame(width: max(room * block.end.timeIntervalSince(block.start) / total, 0))
                        }
                    }
                }
                .frame(height: height)
                .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: blocks)

                HStack(alignment: .firstTextBaseline) {
                    Text(TimeDisplay.time(first.start, pref, includesMeridiem: false))
                    Spacer(minLength: 8)
                    if let lunch {
                        Text("Lunch \(TimeDisplay.range(lunch.start, lunch.end, pref))")
                            .fontWeight(.semibold)
                            .foregroundStyle(StevensonPalette.accent)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .snappy, value: lunch)
                    }
                    Spacer(minLength: 8)
                    Text(TimeDisplay.time(last.end, pref, includesMeridiem: false))
                }
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lunch.map {
                "4th to 6th period run \(TimeDisplay.range(first.start, last.end, pref)), with lunch \(TimeDisplay.range($0.start, $0.end, pref))"
            } ?? "4th to 6th period run \(TimeDisplay.range(first.start, last.end, pref))")
        }
    }

    private func segment(_ block: ResolvedBlock) -> some View {
        let style = style(for: block)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(style.fill)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    if block.role == .lunch {
                        Image(systemName: "fork.knife")
                            .font(.caption.weight(.semibold))
                            .padding(.top, 8)
                        Spacer(minLength: 0)
                    }
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(label(for: block))
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 1)
                    }
                }
                .padding(.bottom, 6)
                .foregroundStyle(style.ink)
            }
    }

    private func label(for block: ResolvedBlock) -> String {
        block.spanLabel ?? block.periodID.periodNumber.map(String.init) ?? ""
    }

    private func style(for block: ResolvedBlock) -> (fill: AnyShapeStyle, ink: AnyShapeStyle) {
        switch block.role {
        case .lunch:
            return (AnyShapeStyle(StevensonPalette.accent), AnyShapeStyle(.white))
        case .advisory:
            let tint = ScheduleStyle.tint(for: .advisory)
            return (AnyShapeStyle(tint.opacity(0.2)), AnyShapeStyle(tint))
        case .free:
            return (AnyShapeStyle(Color.primary.opacity(0.05)), AnyShapeStyle(.secondary))
        default:
            let period = block.periodID.periodNumber
            if !hasLunch, let period, UserConfig.advisoryPeriods.contains(period) {
                return (AnyShapeStyle(StevensonPalette.accent.opacity(0.16)),
                        AnyShapeStyle(StevensonPalette.accent))
            }
            // The plate the tiles and cards sit on, so a class reads as one.
            return (AnyShapeStyle(Color(.secondarySystemGroupedBackground)), AnyShapeStyle(.secondary))
        }
    }
}
