import SwiftUI
import ScheduleKit

/// Where lunch sits is the one part of a Stevenson schedule that moves the
/// bells: a half-period lunch puts one in the middle of 4th, 5th or 6th. This
/// step asks only that, as times: tap the period, then whole or which half.
/// Freshmen add Advisory with one switch. A class running into the other half
/// is left to the classes step, which shows the whole day and can make any
/// class a period and a half. Nothing is saved until Continue.
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

            periodPicker

            if let placement {
                portionPicker(placement)
                if let remaining = placement.remainingHalf {
                    advisorySwitch(placement, remaining: remaining)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip", action: next)
            }
        }
        .sensoryFeedback(.selection, trigger: placement?.period)
        .sensoryFeedback(.selection, trigger: placement?.portion)
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

    /// Three across, or stacked where the largest sizes leave too little room
    /// for the times.
    private var periodPicker: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach(Array(UserConfig.advisoryPeriods), id: \.self) { period in
                periodTile(period, isSelected: placement?.period == period) {
                    select(.period, startingWith: LunchPlacement(period: period)) {
                        $0.period = period
                    }
                }
            }
        }
        .id(Question.period)
    }

    /// A period, filled with the accent once chosen, with its bells.
    private func periodTile(_ period: Int, isSelected: Bool,
                            action: @escaping () -> Void) -> some View {
        let times = times(LunchPlacement(period: period))
        return Button(action: action) {
            VStack(spacing: 4) {
                Text(PeriodID.ordinal(period))
                    .font(.system(.title2, design: .rounded, weight: .bold))
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
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(StevensonPalette.accent)
                                     : AnyShapeStyle(Color(.secondarySystemGroupedBackground))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(PeriodID.ordinal(period)) period, \(times)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Whole period or a half

    /// The whole period or either half, each with the times lunch would run,
    /// so a student who knows when they eat can find it without the A/B names.
    private func portionPicker(_ placement: LunchPlacement) -> some View {
        let portions: [HalfChoice] = [.full, .a, .b]
        return VStack(spacing: 0) {
            ForEach(portions, id: \.self) { portion in
                if portion != portions.first {
                    Divider().padding(.leading, 16)
                }
                portionRow(portion, of: placement)
            }
        }
        .onboardingCard(cornerRadius: 16)
        .id(Question.portion)
    }

    private func portionRow(_ portion: HalfChoice, of placement: LunchPlacement) -> some View {
        let isSelected = placement.portion == portion
        let times = times(LunchPlacement(period: placement.period, portion: portion))
        let title: String
        let detail: String
        switch portion {
        case .full:
            title = "Whole period"
            detail = times
        case .a:
            title = "First half"
            detail = "\(placement.period)A · \(times)"
        case .b:
            title = "Second half"
            detail = "\(placement.period)B · \(times)"
        }

        return Button {
            select(.portion) { $0.portion = portion }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .monospacedDigit()
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

    // MARK: - Advisory

    /// Freshman advisory always takes the half lunch leaves. Everyone else
    /// leaves the switch off: that half is free, and a class that runs into
    /// it is set on the next step.
    private func advisorySwitch(_ placement: LunchPlacement, remaining: Half) -> some View {
        let halfName = "\(placement.period)\(remaining.rawValue)"
        let isOn = Binding(
            get: { placement.otherHalf == .advisory },
            set: { on in
                // Turning it off leaves the half free, whatever the saved
                // placement had there before.
                select(nil) { $0.otherHalf = on ? .advisory : .free }
            })

        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I have Advisory in \(halfName)")
                        .font(.body)
                    Text("Freshmen only")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(StevensonPalette.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .onboardingCard(cornerRadius: 16)

            if placement.otherHalf != .advisory {
                Text("If a class runs into \(halfName), you can set that on the next step.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
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

    /// When lunch runs for a placement, on the Standard schedule.
    private func times(_ placement: LunchPlacement) -> String {
        var config = UserConfig()
        config.setLunchPlacement(placement)
        let lunch = standardTemplate(config: config, catalog: model.catalog)
            .first { $0.role == .lunch }
        return lunch.map { TimeDisplay.range($0.start, $0.end, model.config.timeFormat) } ?? ""
    }
}
