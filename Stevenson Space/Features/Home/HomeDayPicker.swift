import SwiftUI
import ScheduleKit

/// Home's day picker, the first row of the list, so it scrolls away with it:
/// the date (tap for a calendar of any day the catalog knows), and a capsule
/// with a way back to today and previous and next.
struct HomeDayBar: View {
    let day: DayKey
    let today: DayKey
    let select: (DayKey) -> Void
    let showCalendar: () -> Void

    var body: some View {
        // At larger text sizes the capsules no longer fit side by side. Side by
        // side, each keeps its full width, or the stack would wrap "Today" to
        // leave room for the spacer.
        let row = ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                dateButton.fixedSize()
                Spacer(minLength: 0)
                controls.fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                dateButton
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)

        if #available(iOS 26, *) {
            // Zero spacing keeps the two capsules from blending into one.
            GlassEffectContainer(spacing: 0) { row }
        } else {
            row
        }
    }

    private var dateButton: some View {
        let title = HomeDayPicker.title(for: day, today: today)
        return Button(action: showCalendar) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .imageScale(.large)
                    .opacity(0.7)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(.capsule)
        }
        .dayBarCapsule()
        // Named by what it shows, so Voice Control finds it. "Yesterday" and
        // "Tomorrow" show no date, so VoiceOver reads it after them.
        .accessibilityLabel(title)
        .accessibilityValue(title == TimeDisplay.shortDayLabel(day) ? "" : HomeDayPicker.dateLabel(for: day))
        .accessibilityHint("Opens the calendar")
    }

    private var controls: some View {
        HStack(spacing: 0) {
            if day != today {
                Button { select(today) } label: {
                    Text("Today")
                        .font(.body.weight(.medium))
                        .padding(.leading, 14)
                        .padding(.trailing, 8)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Return to today's schedule")
            }
            navigationButton("Previous day", systemImage: "chevron.left", offset: -1)
            navigationButton("Next day", systemImage: "chevron.right", offset: 1)
        }
        .dayBarCapsule()
    }

    private func navigationButton(_ title: LocalizedStringKey, systemImage: String, offset: Int) -> some View {
        let target = day.advanced(by: offset)
        return Button { select(target) } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .imageScale(.large)
                .frame(minWidth: 48, minHeight: 44)
                .contentShape(.rect)
                // The tapped arrow's release animation would also carry its
                // move when Today comes or goes, sliding it across the other.
                .animation(nil, value: day)
        }
        .disabled(!HomeDayPicker.dateRange(today: today).contains(target.date() ?? .distantPast))
        .accessibilityLabel(title)
    }
}

private extension View {
    /// Liquid Glass on iOS 26, like the bar buttons this row stands in for;
    /// a card-coloured capsule before it.
    @ViewBuilder
    func dayBarCapsule() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(Color(.secondarySystemGroupedBackground), in: .capsule)
        }
    }
}

/// The calendar sheet behind the date button, and the dates and labels the
/// day bar shares with it.
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
