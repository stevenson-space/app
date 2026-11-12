import SwiftUI
import UIKit
import ScheduleKit

// MARK: - Classes

struct OnboardingClassesPage: View {
    @Environment(AppModel.self) private var model
    @Environment(OnboardingFlow.self) private var flow

    private var hasClasses: Bool { model.config.hasPersonalSchedule }

    var body: some View {
        OnboardingPage {
            MySchedulePreview()
        } content: {
            OnboardingHeadline(
                eyebrow: "Your schedule",
                title: hasClasses ? "Your classes are in" : "Add your classes",
                message: "Name your classes, add rooms, and set your lunch period. Home, widgets, notifications, and Siri all use them.")
            OnboardingFootnote(text: "You can change this anytime in Settings, under My Schedule.")
        } actions: {
            if hasClasses {
                Button("Continue", action: flow.advance)
                Button("Edit My Classes") { flow.isEditingClasses = true }
                    .onboardingSecondary()
            } else {
                Button("Add My Classes") { flow.isEditingClasses = true }
                Button("Not Now", action: flow.advance)
                    .onboardingSecondary()
            }
        }
    }
}

/// The student's own standard day, the cards Home will show. It updates as
/// they come back from the editor.
private struct MySchedulePreview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let config = model.config
        let pref = config.timeFormat
        VStack(spacing: 8) {
            ForEach(standardTemplate(config: config, catalog: model.catalog).prefix(4)) { block in
                // Worded like the editor's cards, which these lead into.
                ScheduleCardRow(
                    emoji: ScheduleStyle.emoji(for: block, config: config),
                    title: block.displayName,
                    subtitle: [block.spanLabel ?? "Period \(block.periodID.storageKey)",
                               TimeDisplay.range(block.start, block.end, pref), block.room]
                        .compactMap { $0 }.joined(separator: " · ")
                ) { }
            }
        }
        .padding(.horizontal, 20)
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.smooth, value: config)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your schedule")
    }
}

// MARK: - Notifications

struct OnboardingNotificationsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(OnboardingFlow.self) private var flow
    @Environment(\.openURL) private var openURL
    @State private var beforeBell = true
    @State private var specialMornings = true
    @State private var isRequesting = false

    private var isOn: Bool { model.prefs.anyEnabled }

    var body: some View {
        OnboardingPage(stageShare: 0.38) {
            NotificationsDemo(isActive: flow.step == .notifications,
                              beforeBell: isOn ? model.prefs.blockEndEnabled : beforeBell,
                              specialMornings: isOn ? model.prefs.morningEnabled : specialMornings)
        } content: {
            OnboardingHeadline(
                eyebrow: "Notifications",
                title: "A heads-up before the bell",
                message: "Get a reminder before each period ends, and a morning alert when the day runs on a special schedule.")
            choices
            if model.notificationAuthDenied {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications are turned off for SHS Space in iOS Settings.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .tint(StevensonPalette.accent)
                }
            }
            OnboardingFootnote(text: "You can change these anytime in Settings, under Notifications.")
        } actions: {
            if isOn || model.notificationAuthDenied {
                Button("Continue", action: flow.advance)
            } else {
                Button("Turn On Notifications", action: turnOn)
                    .disabled(isRequesting || !(beforeBell || specialMornings))
                Button("Not Now", action: flow.advance)
                    .onboardingSecondary()
            }
        }
        .onChange(of: isOn) { _, isOn in
            // Both live switches just went off. Keep them off rather than
            // showing the pre-permission picks again.
            if !isOn {
                beforeBell = false
                specialMornings = false
            }
        }
    }

    /// Before permission, the switches only pick what to turn on. Afterward
    /// they are the real settings, exactly as in Settings.
    private var choices: some View {
        VStack(spacing: 0) {
            Toggle(isOn: isOn ? liveBinding(\.blockEndEnabled) : $beforeBell) {
                choiceLabel("Before each period ends", detail: leadTime)
            }
            .padding(.horizontal, 16)
            Divider().padding(.leading, 16)
            Toggle(isOn: isOn ? liveBinding(\.morningEnabled) : $specialMornings) {
                choiceLabel("Mornings with special schedules",
                            detail: "At \(morningTime) on Late Arrival, assembly, and finals days")
            }
            .padding(.horizontal, 16)
        }
        .toggleStyle(.switch)
        .tint(StevensonPalette.accent)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .padding(.vertical, 4)
    }

    private func choiceLabel(_ title: LocalizedStringKey, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(.medium))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    /// Settings allows 0 to 15 minutes, and calls 0 "at the bell".
    private var leadTime: String {
        switch model.prefs.blockEndLeadMinutes {
        case 0: "At the bell, with where you're headed next"
        case 1: "1 minute before the bell, with where you're headed next"
        case let minutes: "\(minutes) minutes before the bell, with where you're headed next"
        }
    }

    private var morningTime: String {
        model.today.date(at: model.prefs.morningTime)
            .map { TimeDisplay.time($0, model.config.timeFormat) } ?? "7:00 AM"
    }

    private func liveBinding(_ feature: WritableKeyPath<NotificationPrefs, Bool>) -> Binding<Bool> {
        Binding(get: { model.prefs[keyPath: feature] },
                set: { model.setNotificationFeatureEnabled(feature, $0) })
    }

    private func turnOn() {
        isRequesting = true
        Task {
            let granted = await model.enableNotifications(blockEnd: beforeBell, morning: specialMornings)
            isRequesting = false
            if granted { flow.advance() }
        }
    }
}

/// Lock Screen banners in the planner's own words, one for each switch, so
/// turning one off shows exactly what goes away.
private struct NotificationsDemo: View {
    let isActive: Bool
    let beforeBell: Bool
    let specialMornings: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsMorning = false
    @State private var showsBell = false

    var body: some View {
        let pref = model.config.timeFormat
        let day = OnboardingSample.lunchApproach(catalog: model.catalog)
        VStack(spacing: 10) {
            Text(day.map { TimeDisplay.time($0.chemistry.end.addingTimeInterval(-5 * 60), pref, includesMeridiem: false) } ?? "11:25")
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.bottom, 6)
            if showsMorning {
                banner(title: "Today: Late Arrival",
                       body: "AP Language starts at \(lateArrivalStart(pref)).",
                       time: "4h ago", enabled: specialMornings)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if showsBell, let day {
                banner(title: "Next: \(day.lunch.displayName)",
                       body: "Starts at \(TimeDisplay.time(day.lunch.start, pref))",
                       time: "now", enabled: beforeBell)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 250)
        .background {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.20, blue: 0.30),
                                              Color(red: 0.05, green: 0.07, blue: 0.11)],
                                     startPoint: .top, endPoint: .bottom))
        }
        .padding(.horizontal, 24)
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .task(id: isActive) { await arrive() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example notifications: Today: Late Arrival, and Next: Lunch")
    }

    private func banner(title: String, body: String, time: String, enabled: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(StevensonPalette.green, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(time).font(.caption).foregroundStyle(.secondary)
                }
                Text(body).font(.subheadline)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(enabled ? 1 : 0.25)
        .scaleEffect(enabled ? 1 : 0.97)
        .animation(.smooth, value: enabled)
    }

    private func lateArrivalStart(_ pref: TimeFormatPref) -> String {
        model.catalog.schedule(family: .lateArrival)?.fullBlocks.first
            .flatMap { OnboardingSample.day.date(at: $0.start) }
            .map { TimeDisplay.time($0, pref) } ?? "10:30 AM"
    }

    private func arrive() async {
        guard isActive, !showsBell else { return }
        if reduceMotion {
            showsMorning = true
            showsBell = true
            return
        }
        guard await pause(0.5) else { return }
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) { showsMorning = true }
        guard await pause(0.9) else { return }
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) { showsBell = true }
    }
}
