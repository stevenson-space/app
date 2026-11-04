import SwiftUI
import ScheduleKit

extension View {
    /// Floating chrome over a ground: Liquid Glass on iOS 26, a material
    /// before it. Navigation layer only, never content.
    @ViewBuilder
    func floatingGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

extension EnvironmentValues {
    /// The app's real appearance. Home draws its chrome dark over the green
    /// field even in light mode; views that must not follow that override
    /// (the field itself, sheets) read this instead of `colorScheme`.
    @Entry var appColorScheme: ColorScheme = .light
}

extension Color {
    /// This colour as it resolves in the given appearance, fixed.
    func resolved(for scheme: ColorScheme) -> Color {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return Color(resolve(in: environment))
    }
}

/// A bell time set as a varsity number, with the meridiem small beside it
/// ("10:30 AM" as a big 10:30 and a small AM) so the number fits the hero.
struct BellTimeText: View {
    let date: Date
    let pref: TimeFormatPref
    var size: CGFloat = 96
    var face: Color
    var edge: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(TimeDisplay.time(date, pref, includesMeridiem: false))
                .font(.varsity(size: size))
                .tracking(-size * 0.035)
                .monospacedDigit()
                .foregroundStyle(face)
                .twill(edge, x: size / 32, y: size / 24)
            if let meridiem {
                Text(meridiem)
                    .font(.varsity(.title2))
                    .foregroundStyle(face)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TimeDisplay.time(date, pref))
    }

    private var meridiem: String? {
        guard !TimeDisplay.uses24Hour(pref) else { return nil }
        return SchoolTime.calendar.component(.hour, from: date) < 12 ? "AM" : "PM"
    }
}

extension DayTimeline {
    /// The physical period a span occupies ("3–4A", "4B", "2"), independent of
    /// the class name; nil for blocks outside the numbered periods.
    func periodLabel(for span: ResolvedSpan) -> String? {
        if let label = blocks.first(where: { span.blockIDs.contains($0.id) })?.spanLabel {
            return label
        }
        guard let number = span.periodID?.periodNumber else { return nil }
        return span.half.map { "\(number)\($0.rawValue)" } ?? String(number)
    }
}

/// The ground under Home, and the signature: when a bell changes the ground
/// while the day is live, the new colour rises from the bottom edge over the
/// old one, like the jacket turned to its other side. Any other change (a
/// different day, a rollover) cross-fades, and Reduce Motion always does.
struct FieldBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appColorScheme) private var appColorScheme

    let ground: JacketGround
    let day: DayKey

    @State private var shown: JacketGround?
    @State private var rising: JacketGround?
    @State private var progress: CGFloat = 0

    private struct Change: Equatable {
        let ground: JacketGround
        let day: DayKey
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                (shown ?? ground).background.resolved(for: appColorScheme)
                if let rising {
                    rising.background.resolved(for: appColorScheme)
                        .frame(height: max(proxy.size.height * progress, 0))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onChange(of: Change(ground: ground, day: day)) { old, new in
            guard old.ground != new.ground else { return }
            if shown == nil { shown = old.ground }
            // Settle an unfinished rise before starting the next change.
            if let rising {
                shown = rising
                self.rising = nil
                progress = 0
            }
            if old.day == new.day && !reduceMotion {
                rise(to: new.ground)
            } else {
                withAnimation(.easeInOut(duration: 0.25)) { shown = new.ground }
            }
        }
    }

    private func rise(to newGround: JacketGround) {
        rising = newGround
        progress = 0
        withAnimation(.spring(duration: 0.55, bounce: 0)) {
            progress = 1
        } completion: {
            guard rising == newGround else { return }
            shown = newGround
            rising = nil
            progress = 0
        }
    }
}
