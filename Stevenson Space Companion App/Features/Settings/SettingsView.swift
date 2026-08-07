import SwiftUI
import ScheduleKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                myScheduleSection
                middaySection
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
        Section("My Schedule") {
            NavigationLink {
                PeriodEditorListView()
            } label: {
                Label("Periods & Classes", systemImage: "book")
            }
            Toggle("Hide free periods in the list", isOn: Binding(
                get: { model.config.hideFreePeriods },
                set: { newValue in model.updateConfig { $0.hideFreePeriods = newValue } }))
        }
    }

    // MARK: - Lunch & Advisory

    /// One combined section. Advisory (freshmen only) is never placed
    /// independently: choosing an advisory half automatically puts lunch in
    /// the other half of the same period — advisory 4A ⇒ lunch 4B.
    private var middaySection: some View {
        Section {
            Toggle("I have Advisory (freshmen)", isOn: Binding(
                get: { model.config.hasAdvisory },
                set: { hasAdvisory in
                    model.updateConfig { config in
                        if hasAdvisory {
                            // Seed from the existing lunch choice where possible:
                            // keep the lunch half, advisory takes the other.
                            let base = config.lunch?.basePeriod
                            let period = (base.map { (4...6).contains($0) } == true) ? base! : 4
                            let advisoryHalf: Half = config.lunch?.choice == .a ? .b : .a
                            config.setPairedAdvisory(basePeriod: period, advisoryHalf: advisoryHalf)
                        } else {
                            config.clearAdvisory()
                        }
                    }
                }))

            if model.config.hasAdvisory {
                Picker("Advisory period", selection: Binding(
                    get: { model.config.advisory?.basePeriod ?? 4 },
                    set: { newPeriod in
                        model.updateConfig { config in
                            config.setPairedAdvisory(basePeriod: newPeriod,
                                                     advisoryHalf: advisoryHalf(of: config))
                        }
                    })) {
                    ForEach([4, 5, 6], id: \.self) { period in
                        Text("Period \(period)").tag(period)
                    }
                }

                Picker("Advisory half", selection: Binding(
                    get: { advisoryHalf(of: model.config) },
                    set: { newHalf in
                        model.updateConfig { config in
                            config.setPairedAdvisory(
                                basePeriod: config.advisory?.basePeriod ?? 4,
                                advisoryHalf: newHalf)
                        }
                    })) {
                    Text("A (first half)").tag(Half.a)
                    Text("B (second half)").tag(Half.b)
                }

                if let lunch = model.config.lunch {
                    LabeledContent("Lunch") {
                        Text("\(lunch.displayName) · automatic")
                    }
                }
            } else {
                Picker("Lunch period", selection: Binding(
                    get: { model.config.lunch?.basePeriod },
                    set: { newValue in
                        model.updateConfig { config in
                            if let newValue {
                                let choice = config.lunch?.choice ?? .a
                                config.lunch = SplitAssignment(basePeriod: newValue, choice: choice)
                            } else {
                                config.lunch = nil
                            }
                        }
                    })) {
                    Text("Not set").tag(Int?.none)
                    ForEach([4, 5, 6], id: \.self) { period in
                        Text("Period \(period)").tag(Int?.some(period))
                    }
                }

                if model.config.lunch != nil {
                    Picker("Lunch wave", selection: Binding(
                        get: { model.config.lunch?.choice ?? .a },
                        set: { newValue in
                            model.updateConfig { config in
                                config.lunch?.choice = newValue
                            }
                        })) {
                        ForEach(HalfChoice.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        } header: {
            Text("Lunch & Advisory")
        } footer: {
            if model.config.hasAdvisory {
                Text("Advisory and lunch split the same period: pick your advisory half and lunch automatically takes the other half. On schedules without A/B subdivisions the whole period shows as Lunch.")
            } else {
                Text("On days with A/B subdivisions your lunch shows during that half (e.g. 4A). On schedules without subdivisions — like Late Arrival — the whole period becomes lunch.")
            }
        }
    }

    private func advisoryHalf(of config: UserConfig) -> Half {
        config.advisory?.choice == .b ? .b : .a
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
            }
        } header: {
            Text("Notifications")
        } footer: {
            if model.notificationAuthDenied {
                Text("Notifications are turned off for this app in iOS Settings. Allow them there, then try again.")
                    .foregroundStyle(.orange)
            } else {
                Text("Off by default. Alerts are scheduled a few days ahead from the cached schedule; a same-morning change reaches them the next time the app opens.")
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
        } footer: {
            if !model.overrides.isEmpty {
                Text("Overrides apply to their date only and always win over synced data.")
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
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

            NavigationLink("Data Source") {
                DataSourceEditorView()
            }
        } header: {
            Text("Data & Sync")
        } footer: {
            if let error = model.fetchMetadata.lastError {
                Text("Last sync problem: \(error). The app keeps using its last good copy.")
                    .foregroundStyle(.orange)
            } else {
                Text("Special-day data is shared with stevenson.space and cached for offline use.")
            }
        }
    }
}

struct DataSourceEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Schedule dates URL", text: $urlText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
                Button("Save & Refresh") {
                    save()
                }
                Button("Reset to Default") {
                    model.resetMapURL()
                    urlText = model.mapURL.absoluteString
                    validationMessage = nil
                }
                .disabled(model.store.isUsingDefaultMapURL)
            } header: {
                Text("Remote Map")
            } footer: {
                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                } else {
                    Text("Must be an HTTPS URL returning the schedule-dates JSON. If a fetch fails or the file doesn't parse, the app keeps its last good copy.")
                }
            }
        }
        .navigationTitle("Data Source")
        .onAppear { urlText = model.mapURL.absoluteString }
    }

    private func save() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host() != nil else {
            validationMessage = "That doesn't look like a valid HTTPS URL."
            return
        }
        model.setMapURL(url)
        validationMessage = nil
        dismiss()
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

/// DEBUG-only inspector proving the 64-slot budget and identifier scheme.
struct PendingNotificationsView: View {
    @State private var items: [NotificationScheduler.PendingItem] = []
    @State private var loaded = false

    var body: some View {
        List {
            Section("\(items.count) pending (budget 56 of 64)") {
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
