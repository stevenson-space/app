import SwiftUI
import ScheduleKit

/// The first screen of a new install: Home's own countdown, already running.
/// During school it is the present moment. Outside school hours it previews a
/// moment of the next school day, so there is always a bell being counted down.
struct OnboardingWelcomeView: View {
    @Environment(AppModel.self) private var model

    let start: () -> Void
    let skip: () -> Void

    /// When a previewed moment started counting down: when the screen
    /// appeared, or when the preview last started over.
    @State private var previewStart = Date()
    @State private var pillHeight: CGFloat = 0

    var body: some View {
        let moment = moment

        // The app icon's green, with the countdown in the school's gold: the
        // one screen that is all Stevenson before the steps settle into the
        // app's own grey.
        OnboardingPage(
            centersContent: true,
            ground: StevensonPalette.fieldBottom,
            backdrop: AnyShapeStyle(LinearGradient(
                stops: [.init(color: StevensonPalette.fieldTop, location: 0),
                        .init(color: StevensonPalette.fieldBottom, location: 0.75)],
                startPoint: .top, endPoint: .bottom))
        ) {
            HeroSection(pillHeight: $pillHeight, preview: moment.preview, showsNextLine: false,
                        tint: StevensonPalette.gold)
                .background { BellRings().accessibilityHidden(true) }
                .padding(.top, 12)

            VStack(spacing: 10) {
                Text("Stevenson Space, now an app.")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Adding your classes takes about a minute.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
        } actions: {
            OnboardingPrimaryButton("Set Up My Schedule", tint: StevensonPalette.gold,
                                    ink: StevensonPalette.cardInk, action: start)
            Button("Skip for Now", action: skip)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(minHeight: 44)
        }
        // The field is dark in either appearance, so the text on it is light.
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: moment.previewEnd) {
            // A preview left on screen, or in the background, reaches its
            // bell. Start it over rather than leave the countdown at zero.
            guard let end = moment.previewEnd else { return }
            try? await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
            if !Task.isCancelled { previewStart = Date() }
        }
    }

    // MARK: - The moment on show

    private struct Moment {
        /// Nil shows the present.
        var preview: HeroPreview?
        /// When a previewed countdown reaches its bell, on the real clock.
        var previewEnd: Date?
    }

    private var moment: Moment {
        switch model.currentState {
        case .beforeSchool, .inBlock, .passing:
            return Moment()
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
            return Moment()
        }
        let elapsed = (span.end.timeIntervalSince(span.start) * 0.62).rounded(.down)
        let instant = span.start.addingTimeInterval(elapsed)
        return Moment(
            preview: HeroPreview(state: momentState(at: instant, in: timeline),
                                 offset: instant.timeIntervalSince(previewStart)),
            previewEnd: previewStart.addingTimeInterval(span.end.timeIntervalSince(instant)))
    }

    /// A Standard day to preview when no school day is in reach, as in the
    /// middle of summer, or when the next one has no bells.
    private var regularDay: DayTimeline {
        let day = model.today.advanced(by: 1)
        let standard = DayOverride(day: day, type: .bell(family: .standard, rotation: nil))
        return resolveDay(day, inputs: ResolverInputs(
            overrides: [day: standard], config: model.config, catalog: model.catalog))
    }
}

/// Faint rings spreading out from the dial, like a bell's ring carrying. Drawn
/// at the dial's centre, larger than the screen, so the outer ones run off it.
private struct BellRings: View {
    /// Diameters, as multiples of the dial's 270 pt.
    private static let scales: [CGFloat] = [1.3, 1.72, 2.18, 2.7]

    var body: some View {
        ZStack {
            ForEach(Self.scales, id: \.self) { scale in
                Circle()
                    .stroke(.white.opacity(0.07), lineWidth: 1)
                    .frame(width: 270 * scale, height: 270 * scale)
            }
        }
        // Centred on the hero without widening it.
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
}
