import SwiftUI
import ScheduleKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                myScheduleSection
                notificationsSection
                overrideSection
                DataSyncSection()
                appearanceSection
                aboutSection
                #if DEBUG
                DeveloperSection()
                #endif
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - My schedule

    private var myScheduleSection: some View {
        Section {
            NavigationLink {
                PeriodEditorListView()
            } label: {
                Label("My Schedule", systemImage: "book")
            }
        } header: {
            Text("My Schedule")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle("End-of-period heads-up", isOn: Binding(
                get: { model.prefs.blockEndEnabled },
                set: { newValue in
                    model.setNotificationFeatureEnabled(\.blockEndEnabled, newValue)
                }))

            if model.prefs.blockEndEnabled {
                Stepper(model.prefs.blockEndLeadMinutes == 0
                            ? "Alert at the bell"
                            : "Lead time: \(model.prefs.blockEndLeadMinutes) min",
                        value: Binding(
                            get: { model.prefs.blockEndLeadMinutes },
                            set: { newValue in model.updatePrefs { $0.blockEndLeadMinutes = newValue } }),
                        in: 0...15)
            }

            Toggle("Morning alert on special days", isOn: Binding(
                get: { model.prefs.morningEnabled },
                set: { newValue in
                    model.setNotificationFeatureEnabled(\.morningEnabled, newValue)
                }))

            if model.prefs.morningEnabled {
                DatePicker("Alert time", selection: morningTimeBinding,
                           displayedComponents: .hourAndMinute)
                    // Pin to Chicago so the displayed hour matches the stored
                    // HourMinute regardless of the device's own timezone.
                    .environment(\.calendar, SchoolTime.calendar)
                    .environment(\.timeZone, SchoolTime.timeZone)
            }
        } header: {
            Text("Notifications")
        } footer: {
            if model.notificationAuthDenied {
                Text("Notifications are turned off for this app in iOS Settings. Allow them there, then try again.")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var morningTimeBinding: Binding<Date> {
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

    // MARK: - Override

    private var overrideSection: some View {
        Section {
            NavigationLink {
                OverrideEditorView()
            } label: {
                Label("Set a Day's Schedule", systemImage: "calendar.badge.exclamationmark")
            }
            ForEach(model.overrides, id: \.day) { override in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TimeDisplay.shortDayLabel(override.day))
                            .font(.subheadline.weight(.medium))
                        Text(override.type.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.removeOverride(day: override.day)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Schedule Override")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Color scheme", selection: Binding(
                get: { model.config.appearance },
                set: { newValue in model.updateConfig { $0.appearance = newValue } })) {
                ForEach(AppearancePref.allCases, id: \.self) { pref in
                    Text(pref.displayName).tag(pref)
                }
            }

            Picker("Time format", selection: Binding(
                get: { model.config.timeFormat },
                set: { newValue in model.updateConfig { $0.timeFormat = newValue } })) {
                ForEach(TimeFormatPref.allCases, id: \.self) { pref in
                    Text(pref.displayName).tag(pref)
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version",
                           value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
        }
    }
}

// MARK: - Data & Sync

struct DataSyncSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("Last checked") {
                Text(model.fetchMetadata.lastSuccess?
                    .formatted(.relative(presentation: .named)) ?? "Never")
            }
            LabeledContent("Last data change") {
                Text(model.fetchMetadata.lastChanged?
                    .formatted(date: .abbreviated, time: .shortened) ?? "—")
            }
            if let coverage = model.map?.coverage {
                LabeledContent("Covers") {
                    Text("\(TimeDisplay.shortDayLabel(coverage.start)) – \(TimeDisplay.shortDayLabel(coverage.end))")
                        .font(.caption)
                }
            }

            Button {
                Task { await model.sync(force: true) }
            } label: {
                HStack {
                    Text("Refresh Now")
                    if model.isSyncing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(model.isSyncing)
        } header: {
            Text("Data & Sync")
        } footer: {
            if let error = model.fetchMetadata.lastError {
                Text("Last sync problem: \(error). The app keeps using its last good copy.")
                    .foregroundStyle(.orange)
            }
        }
    }
}

#if DEBUG
/// Time travel: shifts the app's clock so every Home state can be exercised
/// on demand. DEBUG builds only; a banner shows whenever it's active.
struct DeveloperSection: View {
    @Environment(AppModel.self) private var model
    @State private var target = Date()

    private struct Scenario {
        let label: String
        let day: DayKey
        let time: HourMinute
        var override: OverrideType?
    }

    private static let scenarios: [Scenario] = [
        Scenario(label: "Standard · mid class",
                 day: DayKey(year: 2026, month: 9, day: 14), time: HourMinute(hour: 10, minute: 30)),
        Scenario(label: "Standard · passing",
                 day: DayKey(year: 2026, month: 9, day: 14), time: HourMinute(hour: 9, minute: 23)),
        Scenario(label: "Standard · before school",
                 day: DayKey(year: 2026, month: 9, day: 14), time: HourMinute(hour: 7, minute: 50)),
        Scenario(label: "Standard · after school",
                 day: DayKey(year: 2026, month: 9, day: 14), time: HourMinute(hour: 16, minute: 0)),
        Scenario(label: "Late Arrival (override)",
                 day: DayKey(year: 2026, month: 9, day: 15), time: HourMinute(hour: 9, minute: 30),
                 override: .bell(family: .lateArrival, rotation: nil)),
        Scenario(label: "Finals Day 1 (override)",
                 day: DayKey(year: 2026, month: 12, day: 17), time: HourMinute(hour: 8, minute: 45),
                 override: .bell(family: .earlyDismissal, rotation: .rotation1)),
        Scenario(label: "Finals · Makeup zero-gap",
                 day: DayKey(year: 2026, month: 12, day: 17), time: HourMinute(hour: 11, minute: 50),
                 override: .bell(family: .earlyDismissal, rotation: .rotation1)),
        Scenario(label: "PM Assembly (override)",
                 day: DayKey(year: 2026, month: 9, day: 16), time: HourMinute(hour: 14, minute: 50),
                 override: .bell(family: .pmAssembly, rotation: nil)),
        Scenario(label: "Async day (override)",
                 day: DayKey(year: 2026, month: 9, day: 17), time: HourMinute(hour: 10, minute: 0),
                 override: .asynchronous),
        Scenario(label: "Weekend",
                 day: DayKey(year: 2026, month: 9, day: 19), time: HourMinute(hour: 12, minute: 0)),
        Scenario(label: "Winter Break",
                 day: DayKey(year: 2026, month: 12, day: 23), time: HourMinute(hour: 12, minute: 0)),
        Scenario(label: "Summer",
                 day: DayKey(year: 2027, month: 6, day: 15), time: HourMinute(hour: 12, minute: 0)),
    ]

    var body: some View {
        Section("Developer — Time Travel") {
            DatePicker("Jump to", selection: $target)
            Button("Jump") {
                model.timeTravelOffset = target.timeIntervalSince(Date())
            }
            Button("Back to real time") {
                model.timeTravelOffset = 0
            }
            .disabled(!model.isTimeTraveling)
            LabeledContent("App clock") {
                Text(model.now().formatted(date: .abbreviated, time: .standard))
                    .monospacedDigit()
            }
        }

        Section("Developer — Scenarios") {
            ForEach(Self.scenarios, id: \.label) { scenario in
                Button(scenario.label) {
                    // Shift the clock first so the override's reschedule pass
                    // plans from the traveled date.
                    if let instant = scenario.day.date(at: scenario.time) {
                        model.timeTravelOffset = instant.timeIntervalSince(Date())
                    }
                    if let override = scenario.override {
                        model.setOverride(day: scenario.day, type: override)
                    }
                    model.selectedTab = .home
                }
            }
            Button("Clear demo overrides", role: .destructive) {
                for scenario in Self.scenarios where scenario.override != nil {
                    model.removeOverride(day: scenario.day)
                }
            }
        }

        Section("Developer — Notifications") {
            NavigationLink("Pending notification queue") {
                PendingNotificationsView()
            }
        }
    }
}

/// DEBUG-only inspector proving the schedule budget and reserved refresh slot.
struct PendingNotificationsView: View {
    @State private var items: [NotificationScheduler.PendingItem] = []
    @State private var loaded = false

    var body: some View {
        List {
            Section("\(items.count) pending (budget 57 of 64)") {
                if items.isEmpty && loaded {
                    Text("Queue is empty.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline)
                        Text(item.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        if let fire = item.fire {
                            Text(fire.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Pending Queue")
        .task {
            items = await NotificationScheduler.shared.pendingItems()
            loaded = true
        }
        .refreshable {
            items = await NotificationScheduler.shared.pendingItems()
        }
    }
}
#endif
