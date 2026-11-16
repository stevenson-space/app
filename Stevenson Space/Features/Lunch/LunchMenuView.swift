import SwiftUI
import ScheduleKit

struct LunchMenuView: View {
    @Environment(SceneNavigation.self) private var navigation
    @Environment(AppModel.self) private var model
    @State private var selectedDay: DayKey?

    /// Observed, unlike `model.today` (a clock read), so the week strip and
    /// the preferred day roll over at midnight while the tab stays open.
    private var today: DayKey { model.todayTimeline.day }
    private var preferredDay: DayKey {
        model.preferredLunchDay(startingAt: today)
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
                VStack(alignment: .leading, spacing: 32) {
                    UpdateCheckSection(
                        title: "Lunch menu updates",
                        metadata: model.lunchFetchMetadata,
                        isChecking: model.isLunchSyncing,
                        spacing: 24,
                        checkForUpdates: {
                            await model.syncLunch(force: true)
                            return model.lunchFetchMetadata.lastError == nil
                        }
                    ) {
                        WeekPicker(
                            weekdays: weekdays,
                            selectedDay: day,
                            today: today,
                            hasMenu: { model.lunchMenu(for: $0) != nil },
                            select: { selectedDay = $0 },
                            moveWeek: moveWeek)
                    }

                    menuContent
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Jacket.lining)
            .environment(\.jacketGround, .lining)
            .navigationTitle("Lunch")
            .onChange(of: navigation.lunchTodayRequest, initial: true) {
                guard navigation.lunchTodayRequest > 0 else { return }
                selectedDay = today
            }
            .onChange(of: today) { oldDay, _ in
                if selectedDay == oldDay { selectedDay = nil }
            }
            .toolbar {
                if day != preferredDay {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(preferredDay == today ? "Today" : "Next Lunch") {
                            selectedDay = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if let menu = model.lunchMenu(for: day) {
            VStack(alignment: .leading, spacing: 0) {
                Text(LunchDateDisplay.header(day))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Jacket.ink)
                    .accessibilityAddTraits(.isHeader)

                StationList(sections: menu.sections)
                    .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.lunchMenu == nil {
            // No menu ships with the app, so this is every install's state
            // until its first download finishes.
            if model.isLunchSyncing {
                ProgressView("Loading the lunch menu…")
                    .foregroundStyle(Jacket.ink2)
                    .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                ContentUnavailableView {
                    Label("Menu unavailable", systemImage: "fork.knife")
                } description: {
                    Text("The lunch menu could not be downloaded. Check your connection and try again.")
                } actions: {
                    Button("Try Again") {
                        Task { await model.syncLunch(force: true) }
                    }
                }
                .foregroundStyle(Jacket.ink)
                .frame(minHeight: 320)
            }
        } else {
            ContentUnavailableView(
                "No lunch menu",
                systemImage: "calendar.badge.minus",
                description: Text("Lunch is not served on this date, or the published menu does not cover it."))
            .foregroundStyle(Jacket.ink)
            .frame(minHeight: 320)
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(weekLabel)
                    .font(.headline)
                    .foregroundStyle(Jacket.ink)
                    .contentTransition(.numericText())

                Spacer(minLength: 8)

                HStack(spacing: 0) {
                    weekNavigationButton(systemImage: "chevron.left",
                                         accessibilityLabel: "Previous week", offset: -1)
                    weekNavigationButton(systemImage: "chevron.right",
                                         accessibilityLabel: "Next week", offset: 1)
                }
                .background(Capsule().fill(Jacket.ink.opacity(0.07)))
            }

            HStack(spacing: 8) {
                ForEach(weekdays, id: \.self) { candidate in
                    WeekdayButton(
                        day: candidate,
                        weekday: LunchDateDisplay.narrowWeekday(candidate),
                        isSelected: candidate == selectedDay,
                        isToday: candidate == today,
                        hasMenu: hasMenu(candidate),
                        accessibilityLabel: LunchDateDisplay.accessibilityLabel(candidate),
                        select: { select(candidate) })
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    private func weekNavigationButton(systemImage: String, accessibilityLabel: LocalizedStringKey,
                                      offset: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                moveWeek(offset)
            }
        } label: {
            Label(accessibilityLabel, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.subheadline.weight(.semibold))
                .frame(width: 46, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Jacket.accent)
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
}

/// One weekday in the strip. The chosen day is sewn on as a green patch;
/// today carries a gold running stitch under its number.
private struct WeekdayButton: View {
    let day: DayKey
    let weekday: String
    let isSelected: Bool
    let isToday: Bool
    let hasMenu: Bool
    let accessibilityLabel: String
    let select: () -> Void

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                select()
            }
        } label: {
            VStack(spacing: 6) {
                Text(weekday)
                    .jacketLabel()
                    .foregroundStyle(isSelected ? Jacket.onAccent.opacity(0.8) : Jacket.ink2)
                Text("\(day.day)")
                    .font(.varsity(.title2))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(isSelected ? Jacket.onAccent : (hasMenu ? Jacket.ink : Jacket.ink3))
            }
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Jacket.accent)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .inset(by: 4)
                        .stroke(Jacket.onAccent.opacity(0.45),
                                style: StrokeStyle(lineWidth: 1.2, dash: [3.5, 3]))
                }
            }
            .overlay(alignment: .bottom) {
                if isToday {
                    StitchRule(Jacket.twill)
                        .frame(width: 18)
                        .padding(.bottom, 6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if isToday { values.append("Today") }
        if !hasMenu { values.append("No published menu") }
        return values.joined(separator: ", ")
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

/// The day's menu, read like a menu board: the two mains large, the rest in
/// two columns, stations separated by running stitches.
private struct StationList: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let sections: [LunchMenuSection]

    private static let mains: Set<LunchMenuStation> = [.comfort, .mindful]

    var body: some View {
        let mains = sections.filter { Self.mains.contains($0.station) }
        let others = sections.filter { !Self.mains.contains($0.station) }
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: others.count, by: columns).map {
            Array(others[$0..<min($0 + columns, others.count)])
        }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(mains) { section in
                StitchRule(JacketGround.lining.stitch)
                station(section, isMain: true)
                    .padding(.vertical, 16)
            }
            ForEach(rows.indices, id: \.self) { index in
                StitchRule(JacketGround.lining.stitch)
                HStack(alignment: .top, spacing: 20) {
                    ForEach(rows[index]) { section in
                        station(section, isMain: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if rows[index].count < columns {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 16)
            }
        }
    }

    private func station(_ section: LunchMenuSection, isMain: Bool) -> some View {
        VStack(alignment: .leading, spacing: isMain ? 8 : 6) {
            Text(section.station.title)
                .jacketLabel()
                .foregroundStyle(Jacket.ink2)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(section.items, id: \.self) { item in
                    Text(item)
                        .font(isMain ? .title2.weight(.semibold) : .body)
                        .foregroundStyle(Jacket.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "lunch-menu-preview")!
    let model = AppModel(store: SharedStore(defaults: defaults,
                                           secrets: InMemorySecretStore()))
    LunchMenuView()
        .environment(model)
        .environment(SceneNavigation(model: model))
}
