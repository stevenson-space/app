import SwiftUI
import ScheduleKit

/// Visual identity per schedule family and block role. Standard stays quiet;
/// everything abnormal gets a loud color — the design principle is that the
/// app should shout exactly when the day is weird.
enum ScheduleStyle {
    static func accent(for family: BellFamily?) -> Color {
        switch family {
        case .standard, nil: return .secondary
        case .lateArrival: return .purple
        case .odyssey: return .pink
        case .activityPeriod: return .teal
        case .pmAssembly: return .orange
        case .earlyDismissal: return .red
        case .summer: return .orange
        }
    }

    static func icon(for family: BellFamily?) -> String {
        switch family {
        case .standard, nil: return "clock"
        case .lateArrival: return "sunrise.fill"
        case .odyssey: return "sparkles"
        case .activityPeriod: return "person.3.fill"
        case .pmAssembly: return "megaphone.fill"
        case .earlyDismissal: return "graduationcap.fill"
        case .summer: return "sun.max.fill"
        }
    }

    static func tint(for role: BlockRole) -> Color {
        switch role {
        case .classPeriod: return .indigo
        case .lunch: return .green
        case .advisory: return .cyan
        case .free: return .gray
        case .homeroom: return .brown
        case .activity: return .teal
        case .assembly: return .orange
        case .makeup: return .red
        case .summerSchool: return .orange
        }
    }

    static func icon(for role: BlockRole) -> String {
        switch role {
        case .classPeriod: return "book.fill"
        case .lunch: return "fork.knife"
        case .advisory: return "person.2.fill"
        case .free: return "cup.and.saucer.fill"
        case .homeroom: return "house.fill"
        case .activity: return "person.3.fill"
        case .assembly: return "megaphone.fill"
        case .makeup: return "pencil.and.list.clipboard"
        case .summerSchool: return "sun.max.fill"
        }
    }
}
