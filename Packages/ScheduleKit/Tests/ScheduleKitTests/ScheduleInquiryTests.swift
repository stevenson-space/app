import Foundation
import Testing
@testable import ScheduleKit

@Suite struct ScheduleInquiryTests {
    let monday = day(2026, 9, 14)

    @Test func boundariesAndPassingDoNotReportThePreviousClass() throws {
        let inputs = TestSupport.inputs()
        let timeline = resolveDay(monday, inputs: inputs)
        let first = try #require(timeline.blocks.first)
        let before = ScheduleInquiry(at: first.start.addingTimeInterval(-1), inputs: inputs)
        #expect(before.currentClass == nil)
        #expect(before.nextClass?.id == first.id)
        let during = ScheduleInquiry(at: first.start, inputs: inputs)
        #expect(during.currentClass?.id == first.id)
        #expect(during.nextClass?.id == timeline.blocks[1].id)
        let passing = ScheduleInquiry(at: first.end, inputs: inputs)
        #expect(passing.currentClass == nil)
        #expect(passing.currentPeriod == nil)
        #expect(passing.nextClass?.id == timeline.blocks[1].id)
    }

    @Test func lunchAndClassesAreDistinctAndPersonalizationSurvives() {
        let config = UserConfig(lunch: SplitAssignment(basePeriod: 4, choice: .a),
                                customizations: ["4": PeriodCustomization(name: "Biology", room: "2416")])
        let inputs = TestSupport.inputs(config: config)
        let lunch = ScheduleInquiry(at: TestSupport.at(monday, 11, 15), inputs: inputs)
        #expect(lunch.currentPeriod?.role == .lunch)
        #expect(lunch.currentClass == nil)
        #expect(lunch.nextClass?.id == "4B")
        #expect(lunch.nextClass?.displayName == "Biology")
        #expect(lunch.nextClass?.room == "2416")
        let classTime = ScheduleInquiry(at: TestSupport.at(monday, 11, 37), inputs: inputs)
        #expect(classTime.currentClass?.id == "4B")
    }

    @Test func mergedFreeTimeStillReturnsTheActualPeriod() {
        let inputs = TestSupport.inputs(config: UserConfig(freePeriods: [6, 7]))
        let inquiry = ScheduleInquiry(at: TestSupport.at(monday, 14, 0), inputs: inputs)
        #expect(inquiry.currentPeriod?.periodID == .period(7))
        #expect(inquiry.currentClass == nil)
        #expect(inquiry.nextClass?.periodID == .period(8))
        // The display merges this gap into free time; the physical bell schedule
        // correctly has no current period while walking to the next period.
        let passing = ScheduleInquiry(at: TestSupport.at(monday, 13, 43), inputs: inputs)
        #expect(passing.currentPeriod == nil)
    }

    @Test func finalsFollowChronologicalOrderInsteadOfPeriodNumber() throws {
        let map = try TestSupport.map(#"{"Early Dismissal": ["12/17/2026-12/18/2026"]}"#)
        let inputs = TestSupport.inputs(map: map)
        let finals = day(2026, 12, 17)
        let timeline = resolveDay(finals, inputs: inputs)
        let first = try #require(timeline.blocks.first)
        let inquiry = ScheduleInquiry(at: first.start, inputs: inputs)
        #expect(inquiry.currentClass?.periodID == .period(6))
        #expect(inquiry.nextClass?.periodID == .period(2))
    }

    @Test func noSchoolAndAfterSchoolHaveNoClass() throws {
        let inputs = TestSupport.inputs()
        for target in [day(2026, 9, 19), day(2026, 7, 1)] {
            let inquiry = ScheduleInquiry(at: TestSupport.at(target, 10, 0), inputs: inputs)
            #expect(inquiry.currentClass == nil)
            #expect(inquiry.currentPeriod == nil)
            #expect(inquiry.nextClass == nil)
        }
        let last = try #require(resolveDay(monday, inputs: inputs).blocks.last)
        let after = ScheduleInquiry(at: last.end, inputs: inputs)
        #expect(after.currentClass == nil)
        #expect(after.nextClass == nil)
    }

    @Test func manualNoSchoolOverrideWins() {
        let inputs = TestSupport.inputs(overrides: [
            monday: DayOverride(day: monday, type: .noSchool),
        ])
        let inquiry = ScheduleInquiry(at: TestSupport.at(monday, 10, 0), inputs: inputs)
        #expect(inquiry.currentPeriod == nil)
        #expect(inquiry.nextClass == nil)
    }
}
