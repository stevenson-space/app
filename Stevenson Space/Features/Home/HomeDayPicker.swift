import SwiftUI
import ScheduleKit

/// The day picker, as native toolbar items: the date (tap for a calendar of
/// any day the catalog knows), a way back to today, and previous/next.
struct HomeDayToolbar: ToolbarContent {
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
            }
            .accessibilityLabel("Choose schedule date, \(HomeDayPicker.dateLabel(for: day))")
            .accessibilityHint("Opens the calendar")
        }

        if day != today {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { select(today) }
                    .accessibilityLabel("Return to today's schedule")
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            navigationButton("Previous day", icon: "chevron.left", offset: -1)
            navigationButton("Next day", icon: "chevron.right", offset: 1)
        }
    }

    private func navigationButton(_ title: String, icon: String, offset: Int) -> some View {
        let target = day.advanced(by: offset)
        return Button {
            select(target)
        } label: {
            Image(systemName: icon)
        }
        .disabled(!HomeDayPicker.dateRange(today: today).contains(target.date() ?? .distantPast))
        .accessibilityLabel(title)
    }
}

/// The calendar sheet behind the date button, and the date formatting both
/// share.
struct HomeDayPicker: View {
    let day: DayKey
    let today: DayKey
    let select: (DayKey) -> Void
    @Environment(\.dismiss) private var dismiss

    static func dateRange(today: DayKey) -> ClosedRange<Date> {
        let start = SchoolYearCatalog.years.first?.firstDay.date() ?? Date()
        let end = SchoolYearCatalog.years.last?.lastDay.date(at: HourMinute(hour: 23, minute: 59)) ?? start
        let current = today.date() ?? start
        return min(start, current)...max(start, end, current)
    }

    var body: some View {
        let range = Self.dateRange(today: today)
        NavigationStack {
            ScrollView {
                DatePicker("Schedule date", selection: Binding(
                    get: {
                        let date = day.date() ?? today.date() ?? Date()
                        return min(max(date, range.lowerBound), range.upperBound)
                    },
                    set: { select(DayKey(date: $0)) }),
                           in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
            }
            .background(Jacket.lining)
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
        .tint(Jacket.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// "Today", "Tomorrow", or "Mon, Sep 14".
    static func title(for day: DayKey, today: DayKey) -> String {
        if day == today.advanced(by: -1) { return "Yesterday" }
        if day == today.advanced(by: 1) { return "Tomorrow" }
        return TimeDisplay.shortDayLabel(day)
    }

    static func dateLabel(for day: DayKey) -> String {
        guard let date = day.date() else { return day.description }
        var format = Date.FormatStyle(date: .abbreviated, time: .omitted)
        format.calendar = SchoolTime.calendar
        format.timeZone = SchoolTime.timeZone
        return date.formatted(format)
    }
}
