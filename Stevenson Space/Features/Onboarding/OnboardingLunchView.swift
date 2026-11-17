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
            guard !loaded else { return }
            loaded = true
            placement = model.config.lunchPlacement
        }
    }

    // MARK: - Which period

    private var periodPicker: some View {
        // Three across leaves too little room for the times at the largest sizes.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        return layout {
            ForEach(Array(UserConfig.advisoryPeriods), id: \.self) { period in
                let isSelected = placement?.period == period
                Button {
                    select(.period, startingWith: LunchPlacement(period: period)) { $0.period = period }
                } label: {
                    VStack(spacing: 4) {
                        Text(PeriodID.ordinal(period))
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(times(LunchPlacement(period: period)))
                            .font(.caption)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85))
                                                        : AnyShapeStyle(.secondary))
                    }
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(StevensonPalette.accent)
                                             : AnyShapeStyle(Color(.secondarySystemGroupedBackground))))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(PeriodID.ordinal(period)) period, \(times(LunchPlacement(period: period)))")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .id(Question.period)
    }

    // MARK: - How much of it

    private func portionPicker(_ placement: LunchPlacement) -> some View {
        VStack(spacing: 8) {
            OnboardingSectionLabel("How much of \(PeriodID.ordinal(placement.period)) period?")
            Picker("Lunch length", selection: Binding(
                get: { placement.portion },
                set: { portion in select(.portion) { $0.portion = portion } })) {
                Text("All of it").tag(HalfChoice.full)
                Text("\(placement.period)A").tag(HalfChoice.a)
                Text("\(placement.period)B").tag(HalfChoice.b)
            }
            .pickerStyle(.segmented)
        }
        .id(Question.portion)
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

                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(StevensonPalette.accent)
                    .opacity(isSelected ? 1 : 0)
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
