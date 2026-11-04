import SwiftUI
import ScheduleKit

/// Full-screen states for non-school days. Every one of these is deliberate —
/// a student opening the app in July must see something intentional, not a
/// bug. The hero is whatever comes next: the next first bell, or in summer
/// the days left.
struct StatusScreenView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.jacketGround) private var ground
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 96.0

    let timeline: DayTimeline
    let isLive: Bool

    var body: some View {
        let content = content(for: timeline)

        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text(content.title)
            } icon: {
                Image(systemName: content.icon)
                    .font(.title2)
            }
            .labelStyle(StatusTitleLabelStyle())
            .font(.varsity(.largeTitle))
            .foregroundStyle(ground.ink)
            .accessibilityAddTraits(.isHeader)

            Text(content.message)
                .font(.body)
                .foregroundStyle(ground.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            if timeline.provenance == .override {
                Label("Set by you as a manual override", systemImage: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(ground.ink2)
                    .padding(.top, 12)
            }

            if isLive, case .outsideYear = timeline.kind {
                summerCountdown
                    .padding(.top, 56)
            } else if isLive, let next = model.nextSchoolDay {
                NextSchoolDayBlock(next: next, today: model.today, pref: model.config.timeFormat)
                    .padding(.top, 56)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var summerCountdown: some View {
        if let next = model.nextSchoolDay, let days = daysUntil(next.day) {
            VStack(alignment: .leading, spacing: 0) {
                Text("First day of school")
                    .jacketLabel()
                    .foregroundStyle(ground.ink2)
                Text("\(days)")
                    .font(.varsity(size: heroSize))
                    .tracking(-heroSize * 0.035)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(ground.heroFace)
                    .twill(ground.heroEdge, x: heroSize / 32, y: heroSize / 24)
                    .padding(.top, 14)
                Text(days == 1 ? "day to go, on \(TimeDisplay.dayLabel(next.day, relativeTo: model.today))"
                               : "days to go, on \(TimeDisplay.dayLabel(next.day, relativeTo: model.today))")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ground.ink)
                    .padding(.top, 10)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("The next school year isn't in the calendar yet.")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ground.ink)
        }
    }

    private func daysUntil(_ target: DayKey) -> Int? {
        guard let from = model.today.date(), let to = target.date() else { return nil }
        return SchoolTime.calendar.dateComponents([.day], from: from, to: to).day
    }

    private struct Content {
        let icon: String
        let title: String
        let message: String
    }

    private func content(for timeline: DayTimeline) -> Content {
        switch timeline.kind {
        case .weekend:
            return Content(icon: "sun.max", title: "Weekend",
                           message: isLive ? "No school today." : "No school on this date.")
        case .breakDay(let label):
            let icon = label.localizedCaseInsensitiveContains("winter") ? "snowflake"
                : label.localizedCaseInsensitiveContains("spring") ? "leaf"
                : "beach.umbrella"
            return Content(icon: icon, title: label,
                           message: isLive ? "School's out for the break." : "No school during this break.")
        case .noSchool:
            return Content(icon: "moon.zzz", title: "No School",
                           message: isLive ? "There's no school today." : "No school on this date.")
        case .asynchronous:
            return Content(icon: "laptopcomputer", title: "E-Learning Day",
                           message: isLive
                                ? "There is no bell schedule today. Check your classes online for today's work."
                                : "There is no bell schedule on this date. Classwork is online.")
        case .outsideYear:
            return Content(icon: "sun.horizon", title: isLive ? "Summer Break" : "Outside the Calendar",
                           message: isLive
                                ? "School is out, so there's no bell schedule right now."
                                : "This date is outside the supported school years. No bell schedule is available.")
        case .unknownType(let name):
            return Content(icon: "questionmark.circle", title: name,
                           message: "The school calendar marks \(isLive ? "today" : "this date") as “\(name)”, but this version of the app doesn't have its bell schedule.")
        case .school:
            // Never routed here; HomeView shows the schedule for school days.
            return Content(icon: "clock", title: timeline.scheduleLabel, message: "")
        }
    }
}

/// The status title with its symbol above it, small, so the varsity title
/// keeps the margin.
private struct StatusTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.icon
            configuration.title
        }
    }
}
