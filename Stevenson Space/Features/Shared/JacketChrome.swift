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
        ZStack(alignment: .bottom) {
            (shown ?? ground).background.resolved(for: appColorScheme)
            if let rising {
                // A flat colour scaled from the bottom edge looks the same as
                // one growing upward, and animates as a transform.
                rising.background.resolved(for: appColorScheme)
                    .scaleEffect(x: 1, y: progress, anchor: .bottom)
            }
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

/// Navigation bar titles in the jacket's voice: large titles are varsity
/// numbers (SF Pro Expanded Heavy) in the accent with a gold twill edge.
enum JacketAppearance {
    static func configure() {
        let twill = NSShadow()
        twill.shadowColor = UIColor(Jacket.twill)
        twill.shadowOffset = CGSize(width: 2, height: 2.5)
        twill.shadowBlurRadius = 0

        let large = UIFontMetrics(forTextStyle: .largeTitle)
            .scaledFont(for: .systemFont(ofSize: 34, weight: .heavy, width: .expanded))
        let inline = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: .systemFont(ofSize: 17, weight: .bold, width: .expanded))

        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: large,
            .foregroundColor: dynamic(Jacket.accent),
            .shadow: twill,
        ]
        bar.titleTextAttributes = [
            .font: inline,
            .foregroundColor: dynamic(Jacket.ink),
        ]
    }

    private static func dynamic(_ color: Color) -> UIColor {
        let light = UIColor(color.resolved(for: .light))
        let dark = UIColor(color.resolved(for: .dark))
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
}

extension View {
    /// A native grouped form on the jacket's lining: raised rows, the accent
    /// tint, stitched-label headers via `JacketSectionHeader`.
    func jacketForm() -> some View {
        scrollContentBackground(.hidden)
            .background(Jacket.lining)
            .environment(\.jacketGround, .lining)
    }

    /// Rows of a section in a `jacketForm()`.
    func jacketRows() -> some View {
        listRowBackground(Jacket.raised)
    }
}

/// A form section header set as a jacket label.
struct JacketSectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .jacketLabel()
            .foregroundStyle(Jacket.ink2)
    }
}
