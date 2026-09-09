import SwiftUI
import ScheduleKit

struct HomeDayPicker: View {
    let day: DayKey
    let today: DayKey
    let select: (DayKey) -> Void
    @State private var showsCalendar = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                navigationButton("Previous day", icon: "chevron.left", offset: -1)

                Button {
                    showsCalendar = true
                } label: {
                    VStack(spacing: 4) {
                        Text(dayTitle)
                            .font(.headline)
                        Label(dateLabel, systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose schedule date, \(dateLabel)")
                .accessibilityHint("Opens the calendar")

                navigationButton("Next day", icon: "chevron.right", offset: 1)
            }

            if day != today {
                HStack {
                    Text("Schedule preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Today") { select(today) }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .accessibilityLabel("Return to today's schedule")
                }
            }
        }
        .tint(StevensonPalette.accent)
        .sheet(isPresented: $showsCalendar) {
            NavigationStack {
                ScrollView {
                    DatePicker("Schedule date", selection: Binding(
                        get: { day.date() ?? today.date() ?? Date() },
                        set: { select(DayKey(date: $0)) }), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                }
                .navigationTitle("Choose a day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsCalendar = false }
                    }
                }
            }
            .environment(\.calendar, SchoolTime.calendar)
            .environment(\.timeZone, SchoolTime.timeZone)
            .tint(StevensonPalette.accent)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var dayTitle: String {
        if day == today { return "Today" }
        if day == today.advanced(by: -1) { return "Yesterday" }
        if day == today.advanced(by: 1) { return "Tomorrow" }
        guard let date = day.date() else { return "Schedule" }
        var format = Date.FormatStyle().weekday(.wide)
        format.calendar = SchoolTime.calendar
        format.timeZone = SchoolTime.timeZone
        return date.formatted(format)
    }

    private var dateLabel: String {
        guard let date = day.date() else { return day.description }
        var format = Date.FormatStyle(date: .abbreviated, time: .omitted)
        format.calendar = SchoolTime.calendar
        format.timeZone = SchoolTime.timeZone
        return date.formatted(format)
    }

    private func navigationButton(_ title: String, icon: String, offset: Int) -> some View {
        Button {
            select(day.advanced(by: offset))
        } label: {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(StevensonPalette.accent)
        .accessibilityLabel(title)
    }
}
