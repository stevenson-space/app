import SwiftUI
import ScheduleKit

/// Where lunch sits is the one part of a Stevenson schedule that moves the
/// bells: a half-period lunch puts one in the middle of 4th, 5th or 6th. This
/// step asks for it in three taps and shows the result as the cards Home will.
/// Nothing is saved until Continue.
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
        case period, portion, otherHalf
    }

    var body: some View {
        OnboardingPage(revealing: answered) {
            OnboardingHeading(
                title: "When’s your lunch?",
                message: "It decides where the bells fall in the middle of your day.")

            periodPicker

            if let placement {
                portionPicker(placement)
                if let remaining = placement.remainingHalf {
                    otherHalfPicker(placement, remaining: remaining)
                }
                preview(placement)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip", action: next)
            }
        }
        .sensoryFeedback(.selection, trigger: placement)
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
                choiceTile(PeriodID.ordinal(period), times: times(option),
                           accessibilityName: "\(PeriodID.ordinal(period)) period",
                           isSelected: placement?.period == period) {
                    select(.period, startingWith: option) { $0.period = period }
                }
            }
        }
        .id(Question.period)
    }

    // MARK: - How much of it

    private func portionPicker(_ placement: LunchPlacement) -> some View {
        VStack(spacing: 8) {
            OnboardingSectionLabel("How much of \(PeriodID.ordinal(placement.period)) period?")
            tileRow {
                ForEach([HalfChoice.full, .a, .b], id: \.self) { portion in
                    let name = portion == .full ? "Full" : "\(placement.period)\(portion.rawValue)"
                    choiceTile(name, times: times(LunchPlacement(period: placement.period, portion: portion)),
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

    /// One answer, filled with the accent once chosen, with the times lunch
    /// would run if it were the one.
    private func choiceTile(_ title: String, times: String, accessibilityName: String,
                            isSelected: Bool, compact: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: compact ? 2 : 4) {
                Text(title)
                    .font(.system(compact ? .headline : .title2, design: .rounded, weight: .bold))
                Text(times)
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
        .accessibilityLabel("\(accessibilityName), \(times)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - The other half

    private func otherHalfPicker(_ placement: LunchPlacement, remaining: Half) -> some View {
        let halfName = "\(placement.period)\(remaining.rawValue)"
        var options: [LunchPlacement.OtherHalf] = [.free, .advisory]
        if model.config.neighborClassCanFill(placement) { options.append(.neighborClass) }

        return VStack(spacing: 8) {
            OnboardingSectionLabel("And \(halfName)?")
            VStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    if option != options.first {
                        Divider().padding(.leading, 16)
                    }
                    otherHalfRow(option, placement: placement, halfName: halfName)
                }
            }
            .onboardingCard(cornerRadius: 16)
        }
        .id(Question.otherHalf)
    }

    private func otherHalfRow(_ option: LunchPlacement.OtherHalf, placement: LunchPlacement,
                              halfName: String) -> some View {
        let isSelected = placement.otherHalf == option
        let text = otherHalfText(option, placement: placement, halfName: halfName)
        return Button {
            select(.otherHalf) { $0.otherHalf = option }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(text.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(StevensonPalette.accent)
                                                : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func otherHalfText(_ option: LunchPlacement.OtherHalf, placement: LunchPlacement,
                               halfName: String) -> (title: String, detail: String) {
        switch option {
        case .free:
            return ("Free", "Nothing scheduled.")
        case .advisory:
            return ("Advisory", "Freshmen only.")
        case .neighborClass:
            let neighbor = placement.neighborPeriod ?? placement.period
            let name = model.config.customization(for: .period(neighbor))?.name?.nilIfBlank
                ?? "\(PeriodID.ordinal(neighbor)) period class"
            let detail = placement.portion == .b
                ? "It runs a period and a half, through \(halfName)."
                : "It runs a period and a half, starting in \(halfName)."
            return ("My \(name)", detail)
        }
    }

    // MARK: - The result

    /// The three periods a placement can touch, as Home will show them.
    private func preview(_ placement: LunchPlacement) -> some View {
        var config = model.config
        config.setLunchPlacement(placement)
        let pref = config.timeFormat
        let blocks = standardTemplate(config: config, catalog: model.catalog).filter { block in
            guard let number = block.periodID.periodNumber else { return false }
            return abs(number - placement.period) <= 1
        }

        return VStack(spacing: 8) {
            OnboardingSectionLabel("Your midday")
            ForEach(blocks) { block in
                ScheduleCardRow(
                    emoji: ScheduleStyle.emoji(for: block, config: config),
                    title: block.displayName,
                    subtitle: TimeDisplay.range(block.start, block.end, pref),
                    periodLabel: block.periodID.periodNumber.map { block.spanLabel ?? String($0) },
                    showsPeriodBadge: true,
                    highlightTint: block.role == .lunch ? ScheduleStyle.tint(for: .lunch) : nil
                ) { }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Helpers

    /// Changes the draft, or starts one, as the answer to `question`. A half
    /// whose neighbour can't run long into it falls back to free rather than
    /// keeping a choice that is gone.
    private func select(_ question: Question, startingWith initial: LunchPlacement? = nil,
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
        answered = question
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
