import Foundation

/// One notification the app intends to schedule. Pure data — the app target
/// maps it onto UNUserNotificationCenter; nothing here imports UserNotifications
/// so the planner tests run on any platform.
public struct PlannedNotification: Equatable, Hashable, Sendable {
    public let identifier: String
    public let day: DayKey
    /// Chicago wall-clock fire time.
    public let time: HourMinute
    public let title: String
    public let body: String

    public func fireDate(calendar: Calendar = SchoolTime.calendar) -> Date? {
        day.date(at: time, calendar: calendar)
    }
}

/// Computes the full desired notification set from resolved timelines.
///
/// Identifier scheme (stable, prefix-enumerable):
///   `end.<yyyy-mm-dd>.<blockID>` — block-end heads-up
///   `morning.<yyyy-mm-dd>`       — non-standard-day morning alert
///
/// Budgeting: iOS holds at most 64 pending local notifications; we cap at 56
/// and pack whole days chronologically — a day's alerts are all-or-nothing so
/// coverage never silently ends mid-day (except day one, which is always
/// included even if it must be truncated).
public enum NotificationPlanner {
    public static let identifierPrefixes = ["end.", "morning."]
    public static let defaultBudget = 56

    public static func plan(days: [DayTimeline],
                            prefs: NotificationPrefs,
                            now: Date,
                            timeFormat: TimeFormatPref = .twelveHour,
                            budget: Int = defaultBudget,
                            calendar: Calendar = SchoolTime.calendar) -> [PlannedNotification] {
        guard prefs.anyEnabled else { return [] }

        var result: [PlannedNotification] = []

        for timeline in days.sorted(by: { $0.day < $1.day }) {
            var bundle: [PlannedNotification] = []

            if prefs.morningEnabled, let morning = morningAlert(for: timeline, prefs: prefs, timeFormat: timeFormat) {
                if let fire = morning.fireDate(calendar: calendar), fire > now {
                    bundle.append(morning)
                }
            }

            if prefs.blockEndEnabled, timeline.kind == .school {
                let lead = TimeInterval(prefs.blockEndLeadMinutes * 60)
                for (index, span) in timeline.moments.enumerated() where span.role.isAttended {
                    // Blocks shorter than the lead would alert before they start.
                    guard span.end.timeIntervalSince(span.start) > lead else { continue }
                    let fire = span.end.addingTimeInterval(-lead)
                    guard fire > now else { continue }

                    let next = timeline.moments.dropFirst(index + 1).first { $0.role.isAttended }
                    let nextLine: String
                    if let next {
                        nextLine = "Next: \(next.displayName) at \(Self.timeString(next.start, timeFormat))"
                    } else {
                        nextLine = "Last block of the day"
                    }
                    let fireComponents = calendar.dateComponents(
                        [.hour, .minute], from: fire)
                    // Zero lead means "at the bell" — phrase it as such.
                    let title = prefs.blockEndLeadMinutes == 0
                        ? "\(span.displayName) is over"
                        : "\(span.displayName) ends in \(prefs.blockEndLeadMinutes) min"
                    bundle.append(PlannedNotification(
                        identifier: "end.\(timeline.day).\(span.id)",
                        day: timeline.day,
                        time: HourMinute(hour: fireComponents.hour ?? 0,
                                         minute: fireComponents.minute ?? 0),
                        title: title,
                        body: nextLine))
                }
            }

            guard !bundle.isEmpty else { continue }
            if result.count + bundle.count > budget {
                if result.isEmpty {
                    result.append(contentsOf: bundle.prefix(budget))
                }
                break
            }
            result.append(contentsOf: bundle)
        }

        return result
    }

    /// Morning alerts fire only for days a student must plan differently:
    /// non-standard bell schedules and async days. Holidays, breaks, and
    /// weekends stay silent — a 7 AM "no school" alert is how apps get deleted.
    private static func morningAlert(for timeline: DayTimeline,
                                     prefs: NotificationPrefs,
                                     timeFormat: TimeFormatPref) -> PlannedNotification? {
        let identifier = "morning.\(timeline.day)"
        switch timeline.kind {
        case .school where !timeline.isStandardSchedule:
            var title = "Today: \(timeline.scheduleLabel)"
            if let note = timeline.dayNote {
                title += " — \(note)"
            }
            let body: String
            if let first = timeline.moments.first {
                body = "\(first.displayName) starts at \(Self.timeString(first.start, timeFormat))."
            } else {
                body = "Check the app for today's schedule."
            }
            return PlannedNotification(identifier: identifier, day: timeline.day,
                                       time: prefs.morningTime, title: title, body: body)
        case .asynchronous:
            return PlannedNotification(
                identifier: identifier, day: timeline.day, time: prefs.morningTime,
                title: "Asynchronous E-Learning Day",
                body: "There is no bell schedule today.")
        default:
            return nil
        }
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = SchoolTime.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }

    private static let twelveHourFormatter = makeFormatter("h:mm a")
    private static let twentyFourHourFormatter = makeFormatter("H:mm")

    private static func uses24Hour(_ pref: TimeFormatPref) -> Bool {
        switch pref {
        case .twentyFourHour: return true
        case .twelveHour: return false
        case .system:
            return DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?
                .contains("H") ?? false
        }
    }

    /// Mirrors the app's `TimeDisplay.time` rule so notification bodies match
    /// what Home shows; reuses static formatters rather than building one per call.
    private static func timeString(_ date: Date, _ pref: TimeFormatPref) -> String {
        (uses24Hour(pref) ? twentyFourHourFormatter : twelveHourFormatter).string(from: date)
    }
}
