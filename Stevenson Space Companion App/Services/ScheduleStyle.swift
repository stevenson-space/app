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

    // MARK: - Card emoji

    /// The emoji shown on a block's card. A stored emoji belongs to a class
    /// (keyed by its anchor period); lunch, advisory, and free time always
    /// use their role defaults.
    static func emoji(for block: ResolvedBlock, config: UserConfig) -> String {
        if block.role == .classPeriod,
           let custom = config.customization(for: block.customizationID)?.emoji?.nilIfBlank {
            return custom
        }
        return emoji(for: block.role, name: block.displayName)
    }

    static func emoji(for role: BlockRole, name: String?) -> String {
        switch role {
        case .lunch: return "🍔"
        case .advisory: return "🧑‍🏫"
        case .free: return "🥳"
        case .homeroom: return "🏠"
        case .activity: return "🎯"
        case .assembly: return "📣"
        case .makeup: return "✏️"
        case .summerSchool: return "☀️"
        case .classPeriod: return subjectEmoji(name)
        }
    }

    /// Best-effort subject guess from the class name; 📚 when nothing matches.
    static func subjectEmoji(_ name: String?) -> String {
        guard let name = name?.lowercased() else { return "📚" }
        let words = name.split(whereSeparator: { !$0.isLetter })
        // Short keywords match whole words ("art" must not fire inside
        // "earth"); longer ones and phrases match anywhere ("precalculus").
        func matches(_ keyword: String) -> Bool {
            switch keyword.count {
            case ...2: return words.contains { String($0) == keyword }
            case 3: return words.contains { $0.hasPrefix(keyword) }
            default: return name.contains(keyword)
            }
        }
        let map: [(keywords: [String], emoji: String)] = [
            (["physics"], "⚛️"),
            (["computer", "programming", "software", "comp sci"], "💻"),
            (["chem"], "🧪"),
            (["bio", "anatomy"], "🧬"),
            (["statistic"], "📊"),
            (["calc", "math", "algebra", "geometry"], "📐"),
            (["gov", "history", "econ", "civic"], "🏛️"),
            (["engineer", "robotic"], "⚙️"),
            (["spanish", "french", "german", "chinese", "japanese", "latin", "language"], "🌍"),
            (["art", "design", "photo"], "🎨"),
            (["music", "band", "orchestra", "choir"], "🎵"),
            (["gym", "wellness", "fitness", "physical ed", "pe"], "🏃"),
            (["english", "literature", "writing", "comp"], "📚"),
        ]
        for entry in map where entry.keywords.contains(where: matches) {
            return entry.emoji
        }
        return "📚"
    }
}
