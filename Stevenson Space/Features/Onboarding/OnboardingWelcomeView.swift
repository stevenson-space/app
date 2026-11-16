import SwiftUI
import ScheduleKit

/// The first screen of a new install: Home's own countdown, already running.
/// During school it is the present moment. Outside school hours it previews a
/// moment of the next school day, so there is always a bell being counted down.
struct OnboardingWelcomeView: View {
    @Environment(AppModel.self) private var model

    let start: () -> Void
    let skip: () -> Void

    /// When the screen appeared. A previewed moment counts down from here.
    @State private var appeared = Date()
    @State private var pillHeight: CGFloat = 0

    var body: some View {
        let moment = moment

        OnboardingPage {
            VStack(spacing: 16) {
                Label(moment.caption, systemImage: moment.preview == nil ? "clock" : "calendar")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HeroSection(pillHeight: $pillHeight, preview: moment.preview)
            }
            .padding(.top, 12)

            VStack(spacing: 10) {
                Text("Every bell, counted down.")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Stevenson’s schedule to the second, Late Arrival, assemblies and finals included.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Adding your classes takes about a minute. No account needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
        } actions: {
            OnboardingPrimaryButton("Set Up My Schedule", action: start)
            Button("Skip for Now", action: skip)
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - The moment on show

    private struct Moment {
        let caption: String
        /// Nil shows the present.
        let preview: HeroPreview?
    }

    private var moment: Moment {
        switch model.currentState {
        case .beforeSchool, .inBlock, .passing:
            return Moment(caption: caption("Right now", on: model.todayTimeline), preview: nil)
        default:
            return previewMoment
        }
    }

    /// Part-way through the second block of the next school day: a class in
    /// progress with another after it.
    private var previewMoment: Moment {
        let upcoming = model.nextSchoolDay.flatMap { $0.moments.isEmpty ? nil : $0 }
        let timeline = upcoming ?? regularDay
        let spans = timeline.moments
        guard let span = spans.dropFirst().first ?? spans.first else {
            return Moment(caption: "", preview: nil)
        }
        let elapsed = (span.end.timeIntervalSince(span.start) * 0.62).rounded(.down)
        let instant = span.start.addingTimeInterval(elapsed)
        let day = upcoming == nil
            ? "A regular school day"
            : TimeDisplay.dayLabel(timeline.day, relativeTo: model.today)
        let time = TimeDisplay.time(instant, model.config.timeFormat)
        return Moment(
            caption: caption("\(day) at \(time)", on: timeline),
            preview: HeroPreview(state: momentState(at: instant, in: timeline),
                                 offset: instant.timeIntervalSince(appeared)))
    }

    /// A Standard day to preview when no school day is in reach, as in the
    /// middle of summer, or when the next one has no bells.
    private var regularDay: DayTimeline {
        let day = model.today.advanced(by: 1)
        let standard = DayOverride(day: day, type: .bell(family: .standard, rotation: nil))
        return resolveDay(day, inputs: ResolverInputs(
            overrides: [day: standard], config: model.config, catalog: model.catalog))
    }

    /// Quiet on a Standard day, like Home; any other schedule is named.
    private func caption(_ moment: String, on timeline: DayTimeline) -> String {
        timeline.isStandardSchedule ? moment : "\(moment) · \(timeline.scheduleLabel)"
    }
}
