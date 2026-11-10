import Testing
@testable import ScheduleKit

/// The automatic card icon for a class name. Pins the documented rule order
/// and each kind of match so the rule table can change shape safely.
@Suite struct SubjectEmojiTests {
    @Test func specificCoursesBeatBroaderSubjects() {
        #expect(ScheduleStyle.subjectEmoji("Game Programming") == "🎮")
        #expect(ScheduleStyle.subjectEmoji("Art History") == "🎨")
        #expect(ScheduleStyle.subjectEmoji("World History") == "🏛️")
    }

    @Test func prefixesAbbreviationsAndPhrasesAllMatch() {
        #expect(ScheduleStyle.subjectEmoji("AP Statistics") == "📊")
        #expect(ScheduleStyle.subjectEmoji("Chemistry") == "🧪")
        #expect(ScheduleStyle.subjectEmoji("APUSH") == "🏛️")
        #expect(ScheduleStyle.subjectEmoji("Physical Education") == "🏃")
    }

    @Test func unknownOrMissingNamesFallBackToBooks() {
        #expect(ScheduleStyle.subjectEmoji(nil) == "📚")
        #expect(ScheduleStyle.subjectEmoji("") == "📚")
        #expect(ScheduleStyle.subjectEmoji("Study Hall") == "📚")
    }
}
