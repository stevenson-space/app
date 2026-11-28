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

            LunchDayStrip(blocks: dayWithDraft, borrowed: borrowedHalf,
                          pref: model.config.timeFormat, hasLunch: placement != nil)

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
                    .foregroundStyle(isSelected ? AnyShapeStyle(StevensonPalette.onAccent.opacity(0.85))
                                                : AnyShapeStyle(.secondary))
            }
            .foregroundStyle(isSelected ? StevensonPalette.onAccent : .primary)
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
    /// draft, for the strip, along with a class next door running long into
    /// one of them. Lunch can only fall there, so the rest of the day is left
    /// out to give these periods the room.
    private var dayWithDraft: [ResolvedBlock] {
        var config = model.config
        config.setLunchPlacement(placement)
        let day = standardTemplate(config: config, catalog: model.catalog)
        let lunchPeriods = standardTemplate(config: UserConfig(), catalog: model.catalog).filter {
            $0.periodID.periodNumber.map(UserConfig.advisoryPeriods.contains) ?? false
        }
        guard let start = lunchPeriods.map(\.start).min(),
              let end = lunchPeriods.map(\.end).max() else { return day }
        return day.filter { $0.end > start && $0.start < end }
    }

    /// The half a class next door takes over in the draft by running long.
    private var borrowedHalf: Range<Date>? {
        guard let placement, placement.otherHalf == .neighborClass,
              model.config.neighborClassCanFill(placement),
              let half = remainingHalfTimes(placement) else { return nil }
        return half.start..<half.end
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
/// or splits into halves with lunch in one. A class next door that runs long
/// into the other half slides in and stretches over it. Before a choice the
/// periods are tinted.
private struct LunchDayStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var height = 58.0

    let blocks: [ResolvedBlock]
    /// The half a class next door takes over by running long, if one does.
    let borrowed: Range<Date>?
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
                        // A class keeps its place as it grows into 1½ periods.
                        ForEach(blocks, id: \.stripID) { block in
                            let ownPart = ownPart(of: block)
                            LunchStripSegment(
                                label: label(for: block), isLunch: block.role == .lunch,
                                style: style(for: block), ownPart: ownPart,
                                showsLabel: !dynamicTypeSize.isAccessibilitySize)
                            .frame(width: max(room * block.end.timeIntervalSince(block.start) / total, 0))
                            .transition(ownPart.map { .move(edge: $0.edge == .leading ? .leading : .trailing) }
                                        ?? .opacity)
                        }
                    }
                }
                .frame(height: height)
                .clipped()
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
            .accessibilityLabel(accessibilityLabel(first: first, last: last))
        }
    }

    private func accessibilityLabel(first: ResolvedBlock, last: ResolvedBlock) -> String {
        let periods = [first, last].compactMap(\.periodID.periodNumber).map(PeriodID.ordinal)
        let span = periods.count == 2 ? "\(periods[0]) to \(periods[1]) period" : "The middle of the day"
        let times = TimeDisplay.range(first.start, last.end, pref)
        guard let lunch else { return "\(span) run \(times)" }
        return "\(span) run \(times), with lunch \(TimeDisplay.range(lunch.start, lunch.end, pref))"
    }

    /// For the class that runs long into the borrowed half: how much of the
    /// block is its own period, and which end that is on.
    private func ownPart(of block: ResolvedBlock) -> LunchStripSegment.OwnPart? {
        guard let borrowed, block.role == .classPeriod,
              block.start <= borrowed.lowerBound, block.end >= borrowed.upperBound else { return nil }
        let length = block.end.timeIntervalSince(block.start)
        guard length > 0 else { return nil }
        if block.start < borrowed.lowerBound {
            return .init(share: borrowed.lowerBound.timeIntervalSince(block.start) / length, edge: .leading)
        }
        if block.end > borrowed.upperBound {
            return .init(share: block.end.timeIntervalSince(borrowed.upperBound) / length, edge: .trailing)
        }
        return nil
    }

    private func label(for block: ResolvedBlock) -> String {
        block.spanLabel ?? block.periodID.periodNumber.map(String.init) ?? ""
    }

    private func style(for block: ResolvedBlock) -> LunchStripSegment.Style {
        switch block.role {
        case .lunch:
            return .init(fill: AnyShapeStyle(StevensonPalette.accent), ink: AnyShapeStyle(StevensonPalette.onAccent))
        case .advisory:
            let tint = ScheduleStyle.tint(for: .advisory)
            return .init(fill: AnyShapeStyle(tint.opacity(0.2)), ink: AnyShapeStyle(tint))
        case .free:
            return .init(fill: AnyShapeStyle(Color.primary.opacity(0.05)), ink: AnyShapeStyle(.secondary))
        default:
            let period = block.periodID.periodNumber
            if !hasLunch, let period, UserConfig.advisoryPeriods.contains(period) {
                return .init(fill: AnyShapeStyle(StevensonPalette.accent.opacity(0.16)),
                             ink: AnyShapeStyle(StevensonPalette.accent))
            }
            // The plate the tiles and cards sit on, so a class reads as one.
            return .init(fill: AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                         ink: AnyShapeStyle(.secondary))
        }
    }
}

/// One block of the lunch strip. Lunch is marked by the fork and knife with
/// its number small beneath; any other block shows its number large. A class
/// running long into the borrowed half arrives at its own period's length
/// and then stretches over the half, with a dashed seam where its own period
/// ends, so it reads as 1½ periods.
private struct LunchStripSegment: View {
    struct Style {
        var fill: AnyShapeStyle
        var ink: AnyShapeStyle
    }

    struct OwnPart {
        /// The share of the block that is the class's own period.
        var share: Double
        /// The end of the block the class's own period is on.
        var edge: HorizontalEdge
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    let isLunch: Bool
    let style: Style
    let ownPart: OwnPart?
    let showsLabel: Bool

    /// Whether a class that arrived running long has stretched over the half
    /// it borrows. One that was already in the strip simply grows with it.
    @State private var stretched = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let ownShare = ownPart?.share ?? 1
            let alignment: Alignment = ownPart?.edge == .trailing ? .trailing : .leading
            ZStack(alignment: alignment) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(style.fill)
                    .frame(width: width * (stretched ? 1 : ownShare))
                // The number stays over the class's own period, clear of the seam.
                content
                    .frame(width: width * ownShare)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .overlay {
                if let ownPart, stretched {
                    seam(at: ownPart.edge == .leading ? width * ownPart.share
                                                      : width * (1 - ownPart.share),
                         height: geometry.size.height)
                }
            }
        }
        .onAppear {
            guard !stretched else { return }
            guard ownPart != nil, !reduceMotion else {
                stretched = true
                return
            }
            withAnimation(.snappy(duration: 0.5).delay(0.3)) { stretched = true }
        }
    }

    @ViewBuilder private var content: some View {
        Group {
            if isLunch {
                VStack(spacing: 0) {
                    Image(systemName: "fork.knife")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                    if showsLabel {
                        labelText(.caption2)
                            .padding(.bottom, 6)
                    }
                }
            } else if showsLabel {
                labelText(.title2)
            }
        }
        .foregroundStyle(style.ink)
    }

    private func labelText(_ font: Font.TextStyle) -> some View {
        Text(label)
            .font(.system(font, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 2)
    }

    /// Where the class's own period ends and the borrowed half begins.
    private func seam(at x: CGFloat, height: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: x, y: 8))
            path.addLine(to: CGPoint(x: x, y: height - 8))
        }
        .stroke(style.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))
        .opacity(0.5)
        .transition(.opacity)
    }
}

private extension ResolvedBlock {
    /// A class is keyed by its period, so it keeps its place in the strip
    /// as it grows into a 1½-period block. Anything else by its own id.
    var stripID: String {
        role == .classPeriod ? periodID.storageKey : id
    }
}
