import SwiftUI
import ScheduleKit

/// The last step: the two things worth knowing about before Home. Alerts ask
/// for permission only when one is switched on, and the student ID is an
/// invitation to its own tab, since it needs a screenshot nobody has to hand.
struct OnboardingExtrasView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Ends onboarding, on the given tab or wherever it normally lands.
    let finish: (RootTab?) -> Void

    var body: some View {
        OnboardingPage {
            OnboardingHeading(
                title: "Two extras",
                message: "Both are optional, and both are in the app whenever you want them.")

            alerts
            studentID

            Label("Widgets for your Home Screen and Lock Screen are ready to add too.",
                  systemImage: "square.grid.2x2")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            OnboardingPrimaryButton("Show My Schedule") { finish(nil) }
        }
        .navigationTitle("Step 3 of 3")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Alerts

    private var alerts: some View {
        VStack(spacing: 8) {
            OnboardingSectionLabel("Bell alerts")

            VStack(spacing: 0) {
                alertToggle("End-of-period heads-up", detail: headsUpDetail, feature: \.blockEndEnabled)
                Divider().padding(.leading, 16)
                alertToggle("Morning alert on special days", detail: morningDetail,
                            feature: \.morningEnabled)
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

    private var headsUpDetail: String {
        let minutes = model.prefs.blockEndLeadMinutes
        return minutes == 0
            ? "When each class ends, with what’s next."
            : "\(minutes) minutes before each class ends, with what’s next."
    }

    private var morningDetail: String {
        let time = model.today.date(at: model.prefs.morningTime)
            .map { TimeDisplay.time($0, model.config.timeFormat) } ?? "7:00 AM"
        return "At \(time) on Late Arrival, assembly and finals days."
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
