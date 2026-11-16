import SwiftUI
import ScheduleKit

struct OnboardingFinishPage: View {
    @Environment(AppModel.self) private var model
    @Environment(OnboardingFlow.self) private var flow

    var body: some View {
        OnboardingPage(brand: true) {
            FinalBell(isActive: flow.step == .finish)
        } content: {
            Text("You're all set")
                .font(.largeTitle.bold())
                .tracking(-0.4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 16) {
                status("Classes", systemImage: "list.bullet.rectangle",
                       done: model.config.hasPersonalSchedule,
                       doneText: "Added",
                       laterText: "Add them in Settings, under My Schedule.")
                status("Notifications", systemImage: "bell.badge",
                       done: model.prefs.anyEnabled,
                       doneText: "On",
                       laterText: "Turn them on in Settings, under Notifications.")
                status("Student ID", systemImage: "person.text.rectangle",
                       done: model.studentID != nil,
                       doneText: "Saved",
                       laterText: "Import it from the ID tab.")
            }
            .padding(.vertical, 8)
            Text("See this tour again in Settings, under Welcome Tour.")
                .font(.footnote)
                .foregroundStyle(StevensonPalette.onGreenSecondary)
        } actions: {
            Button("Done", action: flow.finish)
        }
    }

    private func status(_ title: LocalizedStringKey, systemImage: String, done: Bool,
                        doneText: LocalizedStringKey, laterText: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(StevensonPalette.gold)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(done ? doneText : laterText)
                    .font(.subheadline)
                    .foregroundStyle(StevensonPalette.onGreenSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(done ? StevensonPalette.gold : .white.opacity(0.5))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The welcome's ring, closed: the tour's last bell.
private struct FinalBell: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isClosed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 10)
            Circle()
                .trim(from: 0, to: isClosed ? 1 : 0)
                .stroke(StevensonPalette.gold, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "checkmark")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(StevensonPalette.gold)
                .symbolEffect(.bounce, value: isClosed)
                .opacity(isClosed ? 1 : 0)
        }
        .frame(width: 200, height: 200)
        .task(id: isActive) {
            guard isActive, !isClosed else { return }
            if !reduceMotion, !(await pause(0.3)) { return }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0)) { isClosed = true }
        }
        .accessibilityHidden(true)
    }
}

extension UserConfig {
    /// Whether the student has named a class or placed lunch, advisory, or a
    /// free period, as opposed to the eight unnamed periods of a fresh install.
    var hasPersonalSchedule: Bool {
        !customizations.isEmpty || !periodPlans.isEmpty
    }
}
