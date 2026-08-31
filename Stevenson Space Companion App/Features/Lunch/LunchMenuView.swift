import SwiftUI
import ScheduleKit

struct LunchMenuView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedDay: DayKey?

    private var preferredDay: DayKey {
        model.preferredLunchDay(startingAt: model.today)
    }
    private var day: DayKey { selectedDay ?? preferredDay }
    private var weekStart: DayKey {
        let weekday = day.weekday() ?? 2
        let daysAfterMonday = (weekday + 5) % 7
        return day.advanced(by: -daysAfterMonday)
    }
    private var weekdays: [DayKey] {
        (0..<5).map { weekStart.advanced(by: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    WeekPicker(
                        weekdays: weekdays,
                        selectedDay: day,
                        today: model.today,
                        hasMenu: { model.lunchMenu(for: $0) != nil },
                        select: { selectedDay = $0 },
                        moveWeek: moveWeek)

                    menuContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lunch")
            .toolbar {
                if day != preferredDay {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(preferredDay == model.today ? "Today" : "Next Lunch") {
                            selectedDay = nil
                        }
                    }
                }
            }
            .refreshable {
                await model.syncLunch(force: true)
            }
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if let menu = model.lunchMenu(for: day) {
            VStack(alignment: .leading, spacing: 14) {
                Text(LunchDateDisplay.header(day))
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                    ForEach(menu.sections) { section in
                        LunchStationCard(section: section)
                    }
                }

                sourceStatus
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.lunchMenu == nil {
            ContentUnavailableView(
                "Menu unavailable",
                systemImage: "fork.knife.circle",
                description: Text("Pull down to try loading the lunch menu again."))
            .frame(minHeight: 320)
        } else {
            ContentUnavailableView(
                "No lunch menu",
                systemImage: "calendar.badge.minus",
                description: Text("Lunch is not served on this date, or the published menu does not cover it."))
            .frame(minHeight: 320)
        }
    }

    @ViewBuilder
    private var sourceStatus: some View {
        if model.lunchFetchMetadata.lastSuccess == nil,
           model.lunchFetchMetadata.lastError != nil {
            Label("Showing the menu included with the app. Live updates are temporarily unavailable.",
                  systemImage: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        } else if let updated = model.lunchFetchMetadata.lastChanged {
            Text("Menu updated \(updated.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func moveWeek(_ offset: Int) {
        let targetWeek = weekStart.advanced(by: offset * 7)
        let preferredWeekday = min(max((day.weekday() ?? 2) - 2, 0), 4)
        selectedDay = targetWeek.advanced(by: preferredWeekday)
    }
}

private struct WeekPicker: View {
    let weekdays: [DayKey]
    let selectedDay: DayKey
    let today: DayKey
    let hasMenu: (DayKey) -> Bool
    let select: (DayKey) -> Void
    let moveWeek: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { moveWeek(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Previous week")

                Spacer()
                Text(weekLabel)
                    .font(.headline)
                Spacer()

                Button { moveWeek(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Next week")
            }

            HStack(spacing: 6) {
                ForEach(weekdays, id: \.self) { candidate in
                    Button {
                        select(candidate)
                    } label: {
                        VStack(spacing: 6) {
                            Text(shortWeekday(candidate))
                                .font(.caption2.weight(.semibold))
                            Text("\(candidate.day)")
                                .font(.headline.monospacedDigit())
                            Circle()
                                .fill(candidate == today ? Color.green : Color.clear)
                                .frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(candidate == selectedDay ? .white : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(candidate == selectedDay ? Color.green : Color(.secondarySystemGroupedBackground)))
                        .opacity(hasMenu(candidate) || candidate == selectedDay ? 1 : 0.52)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(candidate))
                    .accessibilityAddTraits(candidate == selectedDay ? .isSelected : [])
                }
            }
        }
    }

    private var weekLabel: String {
        guard let first = weekdays.first?.date(), let last = weekdays.last?.date() else {
            return selectedDay.description
        }
        let calendar = SchoolTime.calendar
        if calendar.component(.month, from: first) == calendar.component(.month, from: last) {
            return LunchDateDisplay.monthAndYear(first)
        }
        let firstMonth = LunchDateDisplay.abbreviatedMonth(first)
        let lastMonth = LunchDateDisplay.abbreviatedMonthAndYear(last)
        return "\(firstMonth)–\(lastMonth)"
    }

    private func shortWeekday(_ day: DayKey) -> String {
        LunchDateDisplay.narrowWeekday(day)
    }

    private func accessibilityLabel(_ day: DayKey) -> String {
        LunchDateDisplay.accessibilityLabel(day)
    }
}

private enum LunchDateDisplay {
    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = SchoolTime.calendar
        formatter.timeZone = SchoolTime.timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let headerFormatter = formatter("EEEEMMMMd")
    private static let monthAndYearFormatter = formatter("MMMMy")
    private static let abbreviatedMonthFormatter = formatter("MMM")
    private static let abbreviatedMonthAndYearFormatter = formatter("MMMy")
    private static let narrowWeekdayFormatter = formatter("EEEEE")
    private static let accessibilityFormatter = formatter("EEEEMMMMdy")

    static func header(_ day: DayKey) -> String {
        format(day, using: headerFormatter)
    }

    static func monthAndYear(_ date: Date) -> String {
        monthAndYearFormatter.string(from: date)
    }

    static func abbreviatedMonth(_ date: Date) -> String {
        abbreviatedMonthFormatter.string(from: date)
    }

    static func abbreviatedMonthAndYear(_ date: Date) -> String {
        abbreviatedMonthAndYearFormatter.string(from: date)
    }

    static func narrowWeekday(_ day: DayKey) -> String {
        guard let date = day.date() else { return "" }
        return narrowWeekdayFormatter.string(from: date)
    }

    static func accessibilityLabel(_ day: DayKey) -> String {
        format(day, using: accessibilityFormatter)
    }

    private static func format(_ day: DayKey, using formatter: DateFormatter) -> String {
        guard let date = day.date() else { return day.description }
        return formatter.string(from: date)
    }
}

private struct LunchStationCard: View {
    let section: LunchMenuSection

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: section.station.icon)
                .font(.headline)
                .foregroundStyle(section.station.color)
                .frame(width: 36, height: 36)
                .background(Circle().fill(section.station.color.opacity(0.12)))

            VStack(alignment: .leading, spacing: 5) {
                Text(section.station.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(section.items, id: \.self) { item in
                    Text(item)
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
        .accessibilityElement(children: .combine)
    }
}

private extension LunchMenuStation {
    var title: String {
        switch self {
        case .comfort: return "Comfort Food"
        case .mindful: return "Mindful"
        case .sides: return "Sides"
        case .soup: return "Soup"
        case .international: return "International"
        case .special: return "Special"
        }
    }

    var icon: String {
        switch self {
        case .comfort: return "takeoutbag.and.cup.and.straw.fill"
        case .mindful: return "leaf.fill"
        case .sides: return "carrot.fill"
        case .soup: return "cup.and.saucer.fill"
        case .international: return "globe.americas.fill"
        case .special: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .comfort: return .orange
        case .mindful: return .green
        case .sides: return .yellow
        case .soup: return .red
        case .international: return .blue
        case .special: return .purple
        }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "lunch-menu-preview")!
    LunchMenuView()
        .environment(AppModel(store: SharedStore(defaults: defaults)))
}
