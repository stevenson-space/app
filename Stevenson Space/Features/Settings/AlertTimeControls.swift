import SwiftUI
import ScheduleKit

/// How long before a class ends its heads-up arrives. Settings and onboarding
/// both show it under the heads-up switch.
struct HeadsUpLeadTimeStepper: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let minutes = model.prefs.blockEndLeadMinutes
        Stepper(minutes == 0 ? "Alert at the bell" : "Lead time: \(minutes) min",
                value: Binding(
                    get: { model.prefs.blockEndLeadMinutes },
                    set: { newValue in model.updatePrefs { $0.blockEndLeadMinutes = newValue } }),
                in: 0...15)
    }
}

/// When the morning alert on special days arrives.
struct MorningAlertTimePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DatePicker("Alert time", selection: time, displayedComponents: .hourAndMinute)
            // Pin to Chicago so the displayed hour matches the stored
            // HourMinute regardless of the device's own timezone.
            .environment(\.calendar, SchoolTime.calendar)
            .environment(\.timeZone, SchoolTime.timeZone)
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                model.today.date(at: model.prefs.morningTime) ?? Date()
            },
            set: { newValue in
                let components = SchoolTime.calendar.dateComponents([.hour, .minute], from: newValue)
                model.updatePrefs {
                    $0.morningTime = HourMinute(hour: components.hour ?? 7,
                                                minute: components.minute ?? 0)
                }
            })
    }
}
