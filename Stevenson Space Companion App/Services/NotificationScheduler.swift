import Foundation
import UserNotifications
import ScheduleKit

/// Executes the pure planner's output against UNUserNotificationCenter.
/// Owns nothing about *what* to schedule — only authorization, diffing via a
/// plan hash, and submission.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private var lastPlanHash: Int?

    func ensureAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    func reschedule(days: [DayTimeline], prefs: NotificationPrefs, now: Date) async {
        let center = UNUserNotificationCenter.current()

        guard prefs.anyEnabled else {
            await removeAllOurs(center)
            lastPlanHash = nil
            return
        }

        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            return
        }

        let planned = NotificationPlanner.plan(days: days, prefs: prefs, now: now)
        var hasher = Hasher()
        hasher.combine(planned)
        let planHash = hasher.finalize()
        guard planHash != lastPlanHash else { return }

        // Full replace on change: at most 56 adds, and the hash short-circuit
        // makes the no-op path (app foregrounding with nothing changed) free.
        await removeAllOurs(center)
        for notification in planned {
            guard let fire = notification.fireDate() else { continue }
            var components = SchoolTime.calendar.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fire)
            components.timeZone = SchoolTime.timeZone

            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: notification.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
        }
        lastPlanHash = planHash
    }

    private func removeAllOurs(_ center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { identifier in
            NotificationPlanner.identifierPrefixes.contains { identifier.hasPrefix($0) }
        }
        guard !ours.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    #if DEBUG
    struct PendingItem: Identifiable {
        let id: String
        let fire: Date?
        let title: String
    }

    func pendingItems() async -> [PendingItem] {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending
            .map { request in
                let fire = (request.trigger as? UNCalendarNotificationTrigger)?
                    .nextTriggerDate()
                return PendingItem(id: request.identifier, fire: fire,
                                   title: request.content.title)
            }
            .sorted { ($0.fire ?? .distantFuture) < ($1.fire ?? .distantFuture) }
    }
    #endif
}
