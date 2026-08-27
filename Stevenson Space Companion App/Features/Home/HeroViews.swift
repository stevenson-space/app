import SwiftUI
import ScheduleKit

/// Self-ticking countdown digits. Manual rendering (rather than
/// `Text(timerInterval:)`) so DEBUG time travel shifts it too.
struct TickingCountdown: View {
    let target: Date
    let offset: TimeInterval
    var size: CGFloat = 44
    var tint: Color = .primary

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0)) { context in
            let now = context.date.addingTimeInterval(offset)
            Text(TimeDisplay.countdown(target.timeIntervalSince(now)))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText(countsDown: true))
        }
    }
}

/// The hero dial: progress ring around ticking digits.
struct CountdownDial: View {
    let start: Date
    let end: Date
    let tint: Color
    let offset: TimeInterval
    let label: String
    var sublabel: String?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0)) { context in
            let now = context.date.addingTimeInterval(offset)
            let total = max(end.timeIntervalSince(start), 1)
            let fraction = min(max(now.timeIntervalSince(start) / total, 0), 1)
            let remaining = max(end.timeIntervalSince(now), 0)

            ZStack {
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 6) {
                    Text(TimeDisplay.countdown(remaining))
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 30)
                    Text(label)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                }
            }
            .frame(width: 270, height: 270)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(TimeDisplay.spokenDuration(remaining)) \(label)")
        }
    }
}

/// Zone 2 — switches presentation per moment state. Passing gets a visibly
/// different layout, not just a different color.
struct HeroSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pref = model.config.timeFormat

        ZStack {
            heroContent(pref: pref)
                .id(model.currentSpanID)
                .transition(heroTransition)
        }
        .frame(maxWidth: .infinity)
        .animation(heroAnimation, value: model.currentSpanID)
    }

    @ViewBuilder
    private func heroContent(pref: TimeFormatPref) -> some View {
        switch model.currentState {
        case .beforeSchool(let first):
            VStack(spacing: 14) {
                CountdownDial(
                    start: first.start.addingTimeInterval(-3600),
                    end: first.start,
                    tint: .blue,
                    offset: model.displayOffset,
                    label: "until school starts")
                nextLine(icon: "sunrise", text:
                    "\(first.displayName) starts at \(TimeDisplay.time(first.start, pref))")
            }

        case .inBlock(let current, let next):
            VStack(spacing: 14) {
                CountdownDial(
                    start: current.start,
                    end: current.end,
                    tint: ScheduleStyle.tint(for: current.role),
                    offset: model.displayOffset,
                    label: heroLabel(for: current, pref: pref))
                if let next {
                    nextLine(icon: "arrow.right", text:
                        "Next: \(next.displayName)\(roomSuffix(next)) at \(TimeDisplay.time(next.start, pref))")
                } else if current.role == .free {
                    nextLine(icon: "checkmark", text: "You're free for the rest of the day")
                } else {
                    nextLine(icon: "checkmark", text: "Last block of the day")
                }
            }

        case .passing(_, let to, let kind):
            PassingHero(to: to, kind: kind, offset: model.displayOffset, pref: pref)

        case .afterSchool:
            AfterSchoolHero(next: model.nextSchoolDay, today: model.today, pref: pref)

        default:
            // Non-school day kinds never reach the hero; HomeView routes them
            // to full-screen status views.
            EmptyView()
        }
    }

    private var heroTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.94))
                .combined(with: .offset(y: 18)),
            removal: .opacity
                .combined(with: .scale(scale: 1.03))
                .combined(with: .offset(y: -10))
        )
    }

    private var heroAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.52, dampingFraction: 0.8)
    }

    private func heroLabel(for span: ResolvedSpan, pref: TimeFormatPref) -> String {
        switch span.role {
        case .free:
            return "free — until \(TimeDisplay.time(span.end, pref))"
        case .lunch:
            return "left in Lunch"
        case .advisory:
            return "left in Advisory"
        default:
            return "left in \(span.displayName)"
        }
    }

    private func roomSuffix(_ span: ResolvedSpan) -> String {
        span.room.map { " · Rm \($0)" } ?? ""
    }

    private func nextLine(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// Passing period: banner card, walking icon, countdown to the next block.
/// Deliberately unlike the class dial — a two-second glance must distinguish
/// "keep walking" from "sit down".
struct PassingHero: View {
    let to: ResolvedSpan
    let kind: PassingKind
    let offset: TimeInterval
    let pref: TimeFormatPref

    var body: some View {
        VStack(spacing: 10) {
            Label(kind == .intraPeriod ? "Switching Halves" : "Passing Period",
                  systemImage: "figure.walk")
                .font(.headline)
                .foregroundStyle(.orange)
                .textCase(.uppercase)

            TickingCountdown(target: to.start, offset: offset, size: 46, tint: .orange)

            Text("\(to.displayName)\(to.room.map { " · Rm \($0)" } ?? "") starts at \(TimeDisplay.time(to.start, pref))")
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.orange.opacity(0.12))
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
    }
}

/// After the last bell: done for today, plus what tomorrow looks like.
struct AfterSchoolHero: View {
    let next: DayTimeline?
    let today: DayKey
    let pref: TimeFormatPref

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Done for today")
                .font(.title2.bold())
            if let next {
                NextSchoolDayCard(next: next, today: today, pref: pref)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// "Tomorrow: Late Arrival" — used by after-school, weekend, break screens.
struct NextSchoolDayCard: View {
    let next: DayTimeline
    let today: DayKey
    var pref: TimeFormatPref = .system

    var body: some View {
        let accent = ScheduleStyle.accent(for: next.family)
        HStack(spacing: 10) {
            Image(systemName: next.kind == .asynchronous
                  ? "laptopcomputer" : ScheduleStyle.icon(for: next.family))
                .foregroundStyle(next.kind == .asynchronous ? .blue : accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(TimeDisplay.dayLabel(next.day, relativeTo: today))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(next.scheduleLabel)
                    .font(.subheadline.weight(.semibold))
                if let note = next.dayNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let firstBell = next.firstBell {
                Text(TimeDisplay.time(firstBell, pref))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 24)
    }
}
