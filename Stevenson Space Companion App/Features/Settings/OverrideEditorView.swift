import SwiftUI
import ScheduleKit

/// Manual day-type override: for the morning the school changes plans at 6 AM
/// or the map is wrong. Keyed to a single date; sync never touches it.
/// Choosing Early Dismissal requires picking a rotation — there's no range to
/// infer it from.
struct OverrideEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate = Date()
    @State private var choice: Choice = .lateArrival
    @State private var rotation: EDRotation = .rotation1
    @State private var initialized = false

    enum Choice: String, CaseIterable, Identifiable {
        case standard, lateArrival, odyssey, activityPeriod, pmAssembly
        case earlyDismissal, summer, noSchool, asynchronous

        var id: String { rawValue }

        var label: String {
            switch self {
            case .standard: return "Standard Schedule"
            case .lateArrival: return "Late Arrival"
            case .odyssey: return "Odyssey"
            case .activityPeriod: return "Activity Period"
            case .pmAssembly: return "PM Assembly"
            case .earlyDismissal: return "Early Dismissal (Finals)"
            case .summer: return "Summer School"
            case .noSchool: return "No School"
            case .asynchronous: return "Asynchronous E-Learning"
            }
        }

        func overrideType(rotation: EDRotation) -> OverrideType {
            switch self {
            case .standard: return .bell(family: .standard, rotation: nil)
            case .lateArrival: return .bell(family: .lateArrival, rotation: nil)
            case .odyssey: return .bell(family: .odyssey, rotation: nil)
            case .activityPeriod: return .bell(family: .activityPeriod, rotation: nil)
            case .pmAssembly: return .bell(family: .pmAssembly, rotation: nil)
            case .earlyDismissal: return .bell(family: .earlyDismissal, rotation: rotation)
            case .summer: return .bell(family: .summer, rotation: nil)
            case .noSchool: return .noSchool
            case .asynchronous: return .asynchronous
            }
        }
    }

    private var dateRange: ClosedRange<Date> {
        guard let firstYear = SchoolYearCatalog.years.first,
              let lastYear = SchoolYearCatalog.years.last else {
            let now = Date()
            return now...now
        }
        let start = firstYear.firstDay.date() ?? Date()
        let end = lastYear.lastDay.date(at: HourMinute(hour: 23, minute: 59)) ?? Date()
        return start <= end ? start...end : end...start
    }

    private var selectedDay: DayKey { DayKey(date: selectedDate) }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $selectedDate,
                           in: dateRange, displayedComponents: .date)
                Picker("Schedule", selection: $choice) {
                    ForEach(Choice.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                if choice == .earlyDismissal {
                    Picker("Finals rotation", selection: $rotation) {
                        ForEach(EDRotation.allCases, id: \.self) { rotation in
                            Text(rotation.displayName).tag(rotation)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }

            Section {
                Button("Save Override") {
                    model.setOverride(day: selectedDay, type: choice.overrideType(rotation: rotation))
                    dismiss()
                }
                if model.overrides.contains(where: { $0.day == selectedDay }) {
                    Button("Remove Override for This Date", role: .destructive) {
                        model.removeOverride(day: selectedDay)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Schedule Override")
        .onAppear {
            guard !initialized else { return }
            initialized = true
            // Default to the app's "today" clamped into the school year.
            let today = model.today.date() ?? Date()
            selectedDate = min(max(today, dateRange.lowerBound), dateRange.upperBound)
            prefill(for: DayKey(date: selectedDate))
        }
        .onChange(of: selectedDate) {
            prefill(for: selectedDay)
        }
    }

    private func prefill(for day: DayKey) {
        guard let existing = model.overrides.first(where: { $0.day == day }) else { return }
        switch existing.type {
        case .bell(let family, let existingRotation):
            switch family {
            case .standard: choice = .standard
            case .lateArrival: choice = .lateArrival
            case .odyssey: choice = .odyssey
            case .activityPeriod: choice = .activityPeriod
            case .pmAssembly: choice = .pmAssembly
            case .earlyDismissal:
                choice = .earlyDismissal
                if let existingRotation { rotation = existingRotation }
            case .summer: choice = .summer
            }
        case .noSchool: choice = .noSchool
        case .asynchronous: choice = .asynchronous
        }
    }
}
