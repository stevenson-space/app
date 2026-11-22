import SwiftUI
import ScheduleKit

/// Home's day picker, as native toolbar items: the date (tap for a calendar of
/// any day the catalog knows), a way back to today, and previous and next.
struct HomeDayToolbar: ToolbarContent {
    /// The widest title, Today and both arrows only just fit a 375-pt phone at
    /// the default text size; any larger and the system folds the arrows into
    /// a "More" menu. So these stop growing there, like standard bar buttons,
    /// and larger sizes read them through the Large Content Viewer.
    private static let largestTextSize = DynamicTypeSize.large

    let day: DayKey
    let today: DayKey
    let select: (DayKey) -> Void
    @Binding var showsCalendar: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showsCalendar = true
            } label: {
                HStack(spacing: 5) {
                    Text(HomeDayPicker.title(for: day, today: today))
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .opacity(0.7)
                }
                .fixedSize()
                .dynamicTypeSize(...Self.largestTextSize)
            }
            .accessibilityLabel("Choose schedule date, \(HomeDayPicker.dateLabel(for: day))")
            .accessibilityHint("Opens the calendar")
        }

        if day != today {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { select(today) }
                    .dynamicTypeSize(...Self.largestTextSize)
                    .accessibilityLabel("Return to today's schedule")
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            navigationButton("Previous day", systemImage: "chevron.left", offset: -1)
            navigationButton("Next day", systemImage: "chevron.right", offset: 1)
        }
    }

    private func navigationButton(_ title: LocalizedStringKey, systemImage: String, offset: Int) -> some View {
        let target = day.advanced(by: offset)
        return Button(title, systemImage: systemImage) { select(target) }
            .labelStyle(.iconOnly)
            .disabled(!HomeDayPicker.dateRange(today: today).contains(target.date() ?? .distantPast))
    }
}

/// The calendar sheet behind the date button, and the dates and labels the
/// toolbar shares with it.
struct HomeDayPicker: View {
    let day: DayKey
    let today: DayKey
    let select: (DayKey) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let range = Self.dateRange(today: today)
        NavigationStack {
            ScrollView {
                DatePicker("Schedule date", selection: Binding(
                    get: {
                        let date = day.date() ?? today.date() ?? Date()
                        return min(max(date, range.lowerBound), range.upperBound)
                    },
                    // Home follows each pick behind the sheet; Done or a swipe closes it.
                    set: { select(DayKey(date: $0)) }),
                           in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
            }
            .navigationTitle("Choose a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .environment(\.calendar, SchoolTime.calendar)
        .environment(\.timeZone, SchoolTime.timeZone)
        .tint(StevensonPalette.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Every day the catalog has a school year for, and always today. The
    /// arrows and the calendar share it.
    static func dateRange(today: DayKey) -> ClosedRange<Date> {
        let start = SchoolYearCatalog.years.first?.firstDay.date() ?? Date()
        let end = SchoolYearCatalog.years.last?.lastDay.date(at: HourMinute(hour: 23, minute: 59)) ?? start
        let current = today.date() ?? start
        return min(start, current)...max(start, end, current)
    }

    /// "Yesterday", "Tomorrow", or "Mon, Sep 14". Today keeps its date: the
    /// live hero and the missing Today button already say which day it is.
    static func title(for day: DayKey, today: DayKey) -> String {
        if day == today.advanced(by: -1) { return "Yesterday" }
        if day == today.advanced(by: 1) { return "Tomorrow" }
        return TimeDisplay.shortDayLabel(day)
    }

    /// "Sep 14, 2026", in the school's calendar and time zone.
    static func dateLabel(for day: DayKey) -> String {
        guard let date = day.date() else { return day.description }
        var format = Date.FormatStyle(date: .abbreviated, time: .omitted)
        format.calendar = SchoolTime.calendar
        format.timeZone = SchoolTime.timeZone
        return date.formatted(format)
    }
}
