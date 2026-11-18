import SwiftUI
import ScheduleKit

/// What the widgets look like, drawn with the student's own second class part
/// of the way through, as the welcome showed it. Widgets are added from the
/// Home Screen and Lock Screen, so this only shows them and says where.
struct OnboardingWidgetsPreview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            OnboardingSectionLabel("Widgets")

            VStack(alignment: .leading, spacing: 14) {
                if let sample {
                    scene(sample)
                        .accessibilityHidden(true)
                }
                Text("Keep the countdown on your Home Screen and Lock Screen. Touch and hold either one to add them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .onboardingCard(cornerRadius: 16)
        }
    }

    // MARK: - The moment shown

    private struct Sample {
        let block: ResolvedBlock
        let remaining: TimeInterval
        let clock: String
    }

    private var sample: Sample? {
        let classes = standardTemplate(config: model.config, catalog: model.catalog)
            .filter { $0.role == .classPeriod }
        guard let block = classes.dropFirst().first ?? classes.first else { return nil }
        let length = block.end.timeIntervalSince(block.start)
        let elapsed = (length * 0.62).rounded(.down)
        let clock = TimeDisplay.time(block.start.addingTimeInterval(elapsed),
                                     model.config.timeFormat, includesMeridiem: false)
        return Sample(block: block, remaining: length - elapsed, clock: clock)
    }

    private func countdown(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Drawing

    /// A Home Screen widget beside a Lock Screen, on a wallpaper in the
    /// school's green. Sizes are fixed: it is a picture, scaled as one.
    private func scene(_ sample: Sample) -> some View {
        HStack(alignment: .center, spacing: 14) {
            homeWidget(sample)
            lockScreen(sample)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [StevensonPalette.green, Color(red: 0.05, green: 0.17, blue: 0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .dynamicTypeSize(.large)
    }

    private func homeWidget(_ sample: Sample) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Period ends in")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ScheduleStyle.tint(for: .classPeriod))
            Text(countdown(sample.remaining))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(sample.block.displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            if let room = sample.block.room {
                Text("Room \(room)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(12)
        .frame(width: 120, height: 120, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func lockScreen(_ sample: Sample) -> some View {
        VStack(spacing: 8) {
            Text(sample.clock)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)

            HStack(spacing: 8) {
                // Lock Screen widgets draw in one tint over the wallpaper.
                VStack(spacing: 0) {
                    Text("ENDS IN")
                        .font(.system(size: 7, weight: .semibold))
                    Text("\(Int(sample.remaining) / 60)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.2), in: Circle())

                VStack(alignment: .leading, spacing: 0) {
                    Text("Period ends in")
                        .font(.system(size: 9))
                    Text(countdown(sample.remaining))
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                    Text(sample.block.displayName)
                        .font(.system(size: 10, weight: .semibold))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(.white)
    }
}
