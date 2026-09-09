import SwiftUI
import ScheduleKit

/// Full-screen states for non-school days. Every one of these is deliberate —
/// a user opening the app in July must see something intentional, not a bug.
struct StatusScreenView: View {
    @Environment(AppModel.self) private var model

    let timeline: DayTimeline
    let isLive: Bool

    var body: some View {
        let content = content(for: timeline)

        VStack(spacing: 18) {
            Spacer(minLength: 30)

            Image(systemName: content.icon)
                .font(.system(size: 64))
                .foregroundStyle(content.tint)

            Text(content.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text(content.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if timeline.provenance == .override {
                Label("Set by manual override", systemImage: "pencil")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
            }

            if isLive, case .outsideYear = timeline.kind {
                summerCountdown
            } else if isLive, let next = model.nextSchoolDay {
                VStack(spacing: 6) {
                    Text("NEXT SCHOOL DAY")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                    NextSchoolDayCard(next: next, today: model.today, pref: model.config.timeFormat)
                }
                .padding(.top, 12)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var summerCountdown: some View {
        if let next = model.nextSchoolDay {
            VStack(spacing: 8) {
                if let days = daysUntil(next.day) {
                    Text("School starts in **\(days) day\(days == 1 ? "" : "s")**")
                        .font(.title3)
                }
                NextSchoolDayCard(next: next, today: model.today, pref: model.config.timeFormat)
            }
            .padding(.top, 12)
        } else {
            Text("See you next school year!")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func daysUntil(_ target: DayKey) -> Int? {
        guard let from = model.today.date(), let to = target.date() else { return nil }
        return SchoolTime.calendar.dateComponents([.day], from: from, to: to).day
    }

    private struct Content {
        let icon: String
        let tint: Color
        let title: String
        let message: String
    }

    private func content(for timeline: DayTimeline) -> Content {
        switch timeline.kind {
        case .weekend:
            return Content(icon: "sun.max.fill", tint: .yellow,
                           title: isLive ? "It's the Weekend" : "Weekend",
                           message: isLive ? "No school today." : "No school on this date.")
        case .breakDay(let label):
            let icon = label.localizedCaseInsensitiveContains("winter") ? "snowflake"
                : label.localizedCaseInsensitiveContains("spring") ? "leaf.fill"
                : "beach.umbrella.fill"
            let tint: Color = label.localizedCaseInsensitiveContains("winter") ? .cyan : .green
            return Content(icon: icon, tint: tint,
                           title: label,
                           message: isLive ? "School's out — enjoy the break." : "No school during this break.")
        case .noSchool:
            return Content(icon: "moon.zzz.fill", tint: .indigo,
                           title: "No School",
                           message: isLive ? "Enjoy the day off." : "No school on this date.")
        case .asynchronous:
            return Content(icon: "laptopcomputer", tint: .blue,
                           title: "Asynchronous E-Learning Day",
                           message: isLive
                                ? "There is no bell schedule today. Check your classes online for today's work."
                                : "There is no bell schedule on this date. Classwork is online.")
        case .outsideYear:
            return Content(icon: "sun.horizon.fill", tint: .orange,
                           title: isLive ? "Summer Break" : "Outside the School Calendar",
                           message: isLive
                                ? "School is out — no bell schedule right now."
                                : "This date is outside the supported school years. No bell schedule is available.")
        case .unknownType(let name):
            return Content(icon: "questionmark.circle.fill", tint: .gray,
                           title: name,
                           message: "The school calendar marks this date as “\(name)”, but this version of the app doesn't have its bell schedule.")
        case .school:
            // Never routed here; HomeView shows the schedule for school days.
            return Content(icon: "clock", tint: .secondary,
                           title: timeline.scheduleLabel, message: "")
        }
    }
}
