import SwiftUI

/// Identity per schedule family and block: the symbol a special day's patch
/// carries, and the emoji a class shows. Colour lives in `Jacket`.
public enum ScheduleStyle {
    public static func icon(for family: BellFamily?) -> String {
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

    // MARK: - Card emoji

    /// The emoji shown on a block's card. A stored emoji belongs to a class
    /// (keyed by its anchor period); lunch, advisory, and free time always
    /// use their role defaults.
    public static func emoji(for block: ResolvedBlock, config: UserConfig) -> String {
        if block.role == .classPeriod,
           let custom = config.customization(for: block.customizationID)?.emoji?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return emoji(for: block.role, name: block.displayName)
    }

    public static func emoji(for role: BlockRole, name: String?) -> String {
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

    private typealias SubjectRule = (
        emoji: String,
        prefixes: [String],
        abbreviations: [String],
        phrases: [String]
    )

    // Put specific courses before broader subjects so, for example,
    // "Game Programming" beats computer science and "Art History"
    // beats history. Abbreviations only match complete words.
    // Built once: every card, widget row, and keystroke in the period-name
    // editor asks, so the table must not be rebuilt per call.
    private static let subjectRules: [SubjectRule] = [
        ("📊", ["statistic"], ["stat", "stats", "apstat", "apstats"],
         ["data science", "data sci"]),
        ("🔐", ["cybersecurity", "cyber"], ["cybersec"], []),
        ("📱", ["mobile"], [], ["app development"]),
        ("🎮", ["game", "gaming"], [], []),
        ("🥽", ["virtualization"], ["vr"], ["virtual reality"]),
        ("🖨️", ["print", "publication"], [], []),
        ("🏗️", ["architect", "construction"], ["arch"], ["civil engineering"]),
        ("⚡", ["electrical"], ["ee"], []),
        ("🚗", ["automotive", "driver", "collision"], ["auto"], []),
        ("🛠️", ["weld", "fabricat", "repair"], [], []),
        ("💇", ["cosmetolog"], ["cosmo"], []),
        ("🚒", ["firefight"], [], ["fire fighting"]),
        ("🏊", ["swim", "pool", "lifeguard"], [], []),
        ("🏃", ["fitness", "wellness", "gym"], ["pe"],
         ["physical education", "physical ed", "phys ed", "p e"]),
        ("🩺", ["health", "medic", "nurs"], ["ems", "cna"], []),
        ("🫀", ["anatom", "physiolog"], [],
         ["anatomy and physiology", "human growth"]),
        ("🌱", ["environment", "horticultur"], ["apes", "env", "enviro", "hort"], []),
        ("🌋", ["earth", "geolog"], [], []),
        ("🔭", ["astronom"], ["astro"], []),
        ("🔬", ["research"], ["stem"],
         ["physical science", "physical sci", "phys science", "phys sci"]),
        ("⚛️", ["physics"], ["phys", "apphys", "apphysics"], []),
        ("🧪", ["chem"], ["apchem"], []),
        ("🧬", ["bio"], ["apbio"], []),
        ("🧵", ["fashion", "clothing", "textil"], [], []),
        ("🥗", ["nutrition"], [], []),
        ("🍳", ["culinar", "gourmet", "food"], [], []),
        ("🧸", ["childhood", "child"], [],
         ["early education", "young children"]),
        ("🏠", ["interior"], [],
         ["life by design", "life skills", "independent living", "preparing for life"]),
        ("💰", ["account", "financ", "invest"], ["acct"], []),
        ("📈", ["econom", "macroeconom", "microeconom"],
         ["econ", "macro", "micro", "apecon", "apmacro", "apmicro"], []),
        ("⚖️", ["law", "legal", "crimin", "justice"], ["csi"], []),
        ("💼", ["business", "entrepren", "market"], ["biz"], []),
        ("🧠", ["psycholog", "psych"], ["appsych"], []),
        ("📐", ["calculus", "precalculus", "precalc", "algebra", "geometr",
                 "math", "multivariable", "trig"],
         ["calc", "alg", "geom", "apcalc"], ["linear algebra"]),
        ("⚙️", ["engineer", "robot", "manufactur"], ["pltw"], []),
        ("💻", ["computer", "program", "software", "web"],
         ["cs", "csa", "csp", "apcs", "apcsa", "apcsp", "cset", "cs1", "cs2"],
         ["comp sci", "c s"]),
        ("📷", ["photo"], [], []),
        ("🏺", ["ceramic", "sculpt"], [], []),
        ("💎", ["jewel", "metals"], [], []),
        ("🎬", ["video", "film", "animation", "multimedia"], [],
         ["motion graphics", "visual effects", "media analysis"]),
        ("🎭", ["theat", "acting", "drama", "entertainment"], [], []),
        ("🎹", ["piano"], [], []),
        ("🎸", ["guitar"], [], []),
        ("🎻", ["orchestra"], [], []),
        ("🎺", ["band", "symphonic", "wind"], [], []),
        ("🎤", ["choir", "chorus", "singer", "broadcast"], [], ["public speaking"]),
        ("🎵", ["music"], [], []),
        ("🩰", ["dance", "ballet", "jazz"], [], ["technical skills"]),
        ("📰", ["journal"], [], ["current events"]),
        ("🖌️", ["drawing", "painting"], [], []),
        ("🎨", ["art", "design", "illustrat"], [], ["mixed media"]),
        ("📜", ["mytholog", "folklore", "religion", "philosoph"], [], []),
        ("🏛️", ["govern", "gov", "histor", "civic", "politic"],
         ["apush", "apwh", "apeuro", "apgov", "ush", "whap"],
         ["american studies"]),
        ("🌍", ["spanish", "french", "german", "hebrew", "mandarin", "chinese",
                 "japanese", "japan", "korean", "korea", "italian", "italy",
                 "france", "spain", "latin", "geograph", "multilingual"],
         ["span", "fr", "ger", "heb", "mand", "aphug", "hug"],
         ["world language", "global relations", "human geography"]),
        ("🧗", ["adventure"], [], []),
        ("🤝", ["sociolog", "mentor", "leadership"], ["soc"], []),
        ("🧑‍🏫", ["teach"], [], []),
        ("🎓", ["preparatory"], ["act", "sat"], ["college prep", "keys to success"]),
        ("📝", ["writing", "essay"], [], []),
        ("📚", ["english", "literat", "literacy", "reading", "composition", "oracy"],
         ["eng", "ela", "eld", "lang", "lit", "comp", "aplang", "aplit"], [])
    ]

    /// Best-effort subject guess from the class name; 📚 when nothing matches.
    public static func subjectEmoji(_ name: String?) -> String {
        guard let name else { return "📚" }
        let words = name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let condensedName = words.joined()

        func containsPhrase(_ phrase: String) -> Bool {
            let phraseWords = phrase.split(separator: " ").map(String.init)
            guard !phraseWords.isEmpty, phraseWords.count <= words.count else {
                return false
            }

            return (0...(words.count - phraseWords.count)).contains { start in
                words[start..<(start + phraseWords.count)].elementsEqual(phraseWords)
            }
        }

        for rule in subjectRules {
            let matchesPrefix = rule.prefixes.contains { prefix in
                words.contains { $0.hasPrefix(prefix) }
            }
            let matchesAbbreviation = rule.abbreviations.contains { abbreviation in
                words.contains(abbreviation) || condensedName == abbreviation
            }
            let matchesPhrase = rule.phrases.contains(where: containsPhrase)

            if matchesPrefix || matchesAbbreviation || matchesPhrase {
                return rule.emoji
            }
        }
        return "📚"
    }
}
