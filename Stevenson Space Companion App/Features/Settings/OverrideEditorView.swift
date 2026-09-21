import SwiftUI
import ScheduleKit

/// Manual day-type override: for the morning the school changes plans at 6 AM
/// or the map is wrong. Keyed to a single date; sync never touches it.
/// Choosing Early Dismissal requires picking a rotation — there's no range to
/// infer it from.
struct OverrideEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var initialDay: DayKey? = nil

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
                    .environment(\.calendar, SchoolTime.calendar)
                    .environment(\.timeZone, SchoolTime.timeZone)
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
            } footer: {
                Text("Overrides also update lunch availability in the app and widgets. No School, Asynchronous E-Learning, and Summer School hide lunch. Dishes follow the published calendar date; overrides do not shift the menu rotation or add weekend menus.")
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
            // Use the requested day, or the app's "today", within the school year.
            let date = (initialDay ?? model.today).date() ?? Date()
            selectedDate = min(max(date, dateRange.lowerBound), dateRange.upperBound)
            prefill(for: DayKey(date: selectedDate))
        }
        .onChange(of: selectedDate) {
            prefill(for: selectedDay)
        }
    }

    private func prefill(for day: DayKey) {
        // Always reset from this date's effective schedule. Carrying a previous
        // date's draft into a new date can unintentionally hide its lunch menu.
        let timeline = model.timeline(for: day)
        rotation = timeline.rotation ?? .rotation1
        if let family = timeline.family {
            switch family {
            case .standard: choice = .standard
            case .lateArrival: choice = .lateArrival
            case .odyssey: choice = .odyssey
            case .activityPeriod: choice = .activityPeriod
            case .pmAssembly: choice = .pmAssembly
            case .earlyDismissal:
                choice = .earlyDismissal
            case .summer: choice = .summer
            }
        } else {
            choice = timeline.kind == .asynchronous ? .asynchronous : .noSchool
        }
    }
}
