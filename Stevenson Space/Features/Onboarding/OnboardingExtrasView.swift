import SwiftUI
import ScheduleKit

/// The last step: alerts, the student ID and widgets. Alerts ask for
/// permission only when one is switched on. The student ID is an invitation to
/// its own tab, since it needs a screenshot nobody has to hand, and widgets are
/// only shown, since they are added from the Home Screen and Lock Screen.
struct OnboardingExtrasView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Ends onboarding, on the given tab or wherever it normally lands.
    let finish: (RootTab?) -> Void

    @State private var showsWidgetSteps = false

    var body: some View {
        // Opened at the bottom of the page, the widget steps would otherwise
        // start under the button.
        OnboardingPage(revealing: showsWidgetSteps ? OnboardingWidgetsPreview.cardID : nil) {
            OnboardingHeading(
                title: "Finishing touches",
                message: "All optional. Set them up now or anytime later.")

            alerts
            studentID
            OnboardingWidgetsPreview(showsSteps: $showsWidgetSteps)
        } actions: {
            OnboardingPrimaryButton("Show My Schedule") { finish(nil) }
        }
        .navigationTitle("Step 3 of 3")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { OnboardingProgress(step: 3) }
        }
    }

    // MARK: - Alerts

    private var alerts: some View {
        VStack(spacing: 8) {
            OnboardingSectionLabel("Bell alerts")

            if let sample = headsUpSample {
                AlertPreview(title: sample.title, message: sample.message,
                             isOn: model.prefs.blockEndEnabled)
                    .padding(.bottom, 4)
            }

            VStack(spacing: 0) {
                alertToggle("End-of-period heads-up", detail: "Before each class ends, with what’s next.",
                            feature: \.blockEndEnabled)
                if model.prefs.blockEndEnabled {
                    alertSetting { HeadsUpLeadTimeStepper() }
                }
                Divider().padding(.leading, 16)
                alertToggle("Morning alert on special days",
                            detail: "On Late Arrival, assembly and finals days.",
                            feature: \.morningEnabled)
                if model.prefs.morningEnabled {
                    alertSetting { MorningAlertTimePicker() }
                }
            }
            .onboardingCard(cornerRadius: 16)

            if model.notificationAuthDenied {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notifications are turned off for this app in iOS Settings. Allow them there, then try again.")
                        .foregroundStyle(.orange)
                    if let settings = URL(string: UIApplication.openNotificationSettingsURLString) {
                        Link("Open Settings", destination: settings)
                            .fontWeight(.semibold)
                    }
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func alertToggle(_ title: LocalizedStringKey, detail: String,
                             feature: WritableKeyPath<NotificationPrefs, Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { model.prefs[keyPath: feature] },
            set: { model.setNotificationFeatureEnabled(feature, $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    /// A heads-up the student's day would bring, worded as the alert itself
    /// is: for the first class they named, or else for the day's second block.
    private var headsUpSample: (title: String, message: String)? {
        let config = model.config
        let upcoming = standardTemplate(config: config, catalog: model.catalog)
            .dropFirst()
            .filter { $0.role.isAttended }
        let named = upcoming.first {
            $0.role == .classPeriod && config.customization(for: $0.customizationID)?.name?.nilIfBlank != nil
        }
        guard let next = named ?? upcoming.first else { return nil }
        let starts = "Starts at \(TimeDisplay.time(next.start, model.config.timeFormat))"
        return ("Next: \(next.displayName)", next.room.map { "Room \($0) · \(starts)" } ?? starts)
    }

    /// When an alert that is on arrives, under its switch.
    private func alertSetting(@ViewBuilder control: () -> some View) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 16)
            control()
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Student ID

    private var studentID: some View {
        // Beside the card, large text is left a column a word or two wide.
        let summary = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))

        return VStack(spacing: 8) {
            OnboardingSectionLabel("Student ID")

            VStack(alignment: .leading, spacing: 14) {
                summary {
                    StudentIDCardView(content: model.studentID.map {
                        .card($0, photo: model.studentIDPhotoHidden ? nil : model.studentIDPhoto)
                    } ?? .placeholder)
                        .frame(width: 124)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.studentID == nil ? "Your ID, on your phone" : "Your ID is saved")
                            .font(.headline)
                        Text(model.studentID == nil
                             ? "Import one screenshot from Infinite Campus, then scan it from the ID tab."
                             : "It’s on this device already. Scan it from the ID tab.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if model.studentID == nil {
                    Button {
                        finish(.id)
                    } label: {
                        Text("Add My ID")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Finishes setup and opens the ID tab")
                }
            }
            .padding(16)
            .onboardingCard(cornerRadius: 16)
        }
    }
}

/// A heads-up as it lands on the Lock Screen. Faded while its switch is off,
/// so turning the switch on is seen to turn the alert on.
private struct AlertPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var iconSize = 38.0

    let title: String
    let message: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [StevensonPalette.fieldTop, StevensonPalette.fieldBottom],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: iconSize, height: iconSize)
                .overlay {
                    Image(systemName: "bell.fill")
                        .font(.system(size: iconSize * 0.45, weight: .semibold))
                        .foregroundStyle(StevensonPalette.gold)
                        .symbolEffect(.bounce, value: isOn)
                }

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text("now")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(message)
                    .font(.subheadline)
                    .monospacedDigit()
            }
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(isOn ? 0.1 : 0), radius: 12, y: 4))
        .saturation(isOn ? 1 : 0)
        .opacity(isOn ? 1 : 0.55)
        .scaleEffect(isOn || reduceMotion ? 1 : 0.97)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example heads-up: \(title). \(message)")
    }
}
