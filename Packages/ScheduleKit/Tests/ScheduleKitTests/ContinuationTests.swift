import Testing
import Foundation
@testable import ScheduleKit

/// 1½-period classes: contiguous same-anchor class slots merge into one block
/// on splittable schedules and degrade honestly everywhere else.
@Suite struct ContinuationTests {
    let monday = day(2026, 9, 14) // Standard day

    /// Chemistry occupying period 2 plus 3A, anchored at 2.
    private func chemistryConfig() -> UserConfig {
        var config = UserConfig()
        config.customizations["2"] = PeriodCustomization(name: "AP Chemistry", room: "118")
        config.setClassExtended(anchor: 2, true)
        return config
    }

    private func timeline(_ config: UserConfig, on target: DayKey? = nil,
                          map: DayTypeMap? = nil) -> DayTimeline {
        resolveDay(target ?? monday, inputs: TestSupport.inputs(map: map, config: config))
    }

    // MARK: - Forward extension (period N + (N+1)A)

    @Test func forwardExtensionMergesIntoOneBlock() {
        var config = chemistryConfig()
        config.lunch = SplitAssignment(basePeriod: 3, choice: .b)
        let t = timeline(config)
        let lines = TestSupport.lines(t)

        // One continuous block from period 2's start to 3A's end, spanning the
        // internal passing period — the student never leaves the room.
        #expect(lines.contains("09:26-10:38 2+3A classPeriod AP Chemistry"))
        #expect(lines.contains("10:45-11:05 3B lunch Lunch"))
        #expect(!lines.contains { $0.contains(" 2 ") || $0.contains(" 3A ") })

        let merged = t.blocks.first { $0.id == "2+3A" }
        #expect(merged?.spanLabel == "2–3A")
        #expect(merged?.periodID == .period(2))
        #expect(merged?.half == nil)
        #expect(merged?.room == "118")
    }

    @Test func mergedClassIsOneMomentAndAbsorbsTheInternalBell() {
        var config = chemistryConfig()
        config.lunch = SplitAssignment(basePeriod: 3, choice: .b)
        let t = timeline(config)

        let span = t.moments.first { $0.id == "2+3A" }
        #expect(span != nil)
        #expect(span?.blockIDs == ["2+3A"])

        // 10:15 sits inside the old 2→3 passing gap; for this student it's
        // mid-class, not passing.
        if case .inBlock(let current, _) = momentState(at: TestSupport.at(monday, 10, 15), in: t) {
            #expect(current.id == "2+3A")
        } else {
            Issue.record("expected inBlock during the absorbed passing period")
        }

        // 10:40 is between the merged class and 3B lunch — ordinary passing.
        if case .passing(let from, let to, let kind) = momentState(at: TestSupport.at(monday, 10, 40), in: t) {
            #expect(from.id == "2+3A")
            #expect(to.id == "3B")
            #expect(kind == .betweenPeriods)
        } else {
            Issue.record("expected passing between merged class and lunch")
        }
    }

    @Test func mergedClassGetsASingleEndNotification() {
        var config = chemistryConfig()
        config.lunch = SplitAssignment(basePeriod: 3, choice: .b)
        let t = timeline(config)
        let prefs = NotificationPrefs(blockEndEnabled: true, blockEndLeadMinutes: 2)
        let planned = NotificationPlanner.plan(
            days: [t], prefs: prefs, now: TestSupport.at(monday, 0, 0))

        let chemAlerts = planned.filter { $0.identifier.contains("2+3A") }
        #expect(chemAlerts.count == 1)
        #expect(chemAlerts.first?.time == HourMinute(hour: 10, minute: 36))
        // No phantom alert at period 2's own end.
        #expect(!planned.contains { $0.identifier.hasSuffix(".2") })
    }

    // MARK: - Backward extension ((N-1)B + period N)

    @Test func backwardExtensionMergesAndAnchorsAtTheFullPeriod() {
        var config = UserConfig()
        config.customizations["4"] = PeriodCustomization(name: "Physics", room: "301")
        config.setSlot(period: 3, half: .b, to: .classSlot(anchor: 4))
        config.lunch = SplitAssignment(basePeriod: 3, choice: .a)
        let lines = TestSupport.lines(timeline(config))

        #expect(lines.contains("10:18-10:38 3A lunch Lunch"))
        #expect(lines.contains("10:45-11:57 3B+4 classPeriod Physics"))

        let merged = timeline(config).blocks.first { $0.id == "3B+4" }
        #expect(merged?.spanLabel == "3B–4")
        #expect(merged?.periodID == .period(4))
    }

    @Test func freeHalfNeverInheritsTheStaleClassName() {
        // Period 2's name belongs to its class. When bio extends into 2A and
        // 2B goes free, the free half must not display "AP Chemistry".
        var config = UserConfig()
        config.customizations["1"] = PeriodCustomization(name: "AP Bio")
        config.customizations["2"] = PeriodCustomization(name: "AP Chemistry")
        config.setClassExtended(anchor: 1, true)
        config.setSlot(period: 2, half: .b, to: .free)
        let lines = TestSupport.lines(timeline(config))
        #expect(lines.contains("09:53-10:13 2B free Free Period"))
    }

    @Test func leftoverHalfCanBeFree() {
        var config = chemistryConfig()
        config.setSlot(period: 3, half: .b, to: .free)
        let lines = TestSupport.lines(timeline(config))
        #expect(lines.contains("09:26-10:38 2+3A classPeriod AP Chemistry"))
        #expect(lines.contains("10:45-11:05 3B free Free Period"))
    }

    @Test func backToBackExtendedClassesSplitAtTheAnchorBoundary() {
        var config = chemistryConfig() // chem = 2 + 3A
        config.customizations["4"] = PeriodCustomization(name: "Physics")
        config.setSlot(period: 3, half: .b, to: .classSlot(anchor: 4)) // physics = 3B + 4
        let lines = TestSupport.lines(timeline(config))
        #expect(lines.contains("09:26-10:38 2+3A classPeriod AP Chemistry"))
        #expect(lines.contains("10:45-11:57 3B+4 classPeriod Physics"))
    }

    // MARK: - Migrated half-lunch legacy shapes

    @Test func legacyFreePeriodSharingLunchPeriodStaysFree() {
        // Legacy blob: lunch 4A + period 4 marked free ⇒ 4B renders free.
        let config = UserConfig(lunch: SplitAssignment(basePeriod: 4, choice: .a),
                                freePeriods: [4])
        let lines = TestSupport.lines(timeline(config))
        #expect(lines.contains("11:10-11:30 4A lunch Lunch"))
        #expect(lines.contains("11:37-11:57 4B free Free Period"))
    }

    // MARK: - Non-splittable schedules degrade honestly

    @Test func lateArrivalGivesLunchTheSharedPeriod() throws {
        var config = chemistryConfig()
        config.lunch = SplitAssignment(basePeriod: 3, choice: .b)
        let map = try TestSupport.map(#"{"Late Arrival": ["9/14/2026"]}"#)
        let t = timeline(config, map: map)
        let lines = TestSupport.lines(t)

        #expect(t.family == .lateArrival)
        #expect(lines.contains("11:10-11:40 2 classPeriod AP Chemistry"))
        #expect(lines.contains("11:45-12:15 3 lunch Lunch"))
        #expect(!lines.contains { $0.contains("+") })
    }

    @Test func lateArrivalAttributesAClassFreeMixToTheClass() throws {
        var config = chemistryConfig()
        config.setSlot(period: 3, half: .b, to: .free)
        let map = try TestSupport.map(#"{"Late Arrival": ["9/14/2026"]}"#)
        let lines = TestSupport.lines(timeline(config, map: map))
        // Attended-first: better to sit the tail of a class you didn't have
        // than to skip one you did.
        #expect(lines.contains("11:45-12:15 3 classPeriod AP Chemistry"))
    }

    @Test func earlyDismissalKeepsPeriodsSeparateAndNamesFollowAnchors() throws {
        var config = chemistryConfig()
        config.setSlot(period: 3, half: .b, to: .free)
        let map = try TestSupport.map(#"{"Early Dismissal": ["12/17/2026-12/18/2026"]}"#)
        let t = resolveDay(day(2026, 12, 17), inputs: TestSupport.inputs(map: map, config: config))
        // Rotation 1 runs 6, 2, 3, 4 — periods 2 and 3 are adjacent in day
        // order, but finals slots never merge.
        #expect(t.blocks.map(\.id) == ["6", "2", "3", "4", "makeup"])
        let period3 = t.blocks.first { $0.id == "3" }
        #expect(period3?.displayName == "AP Chemistry")
        #expect(period3?.role == .classPeriod)
        let period2 = t.blocks.first { $0.id == "2" }
        #expect(period2?.displayName == "AP Chemistry")
    }

    // MARK: - Friday advisory on the grid

    @Test func fridayCollapsesAdvisoryToFullLunchButKeepsMergedClasses() {
        var config = chemistryConfig()
        config.setSlot(period: 3, half: .b, to: .free)
        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .a)

        let friday = timeline(config, on: day(2026, 9, 18))
        let fridayLines = TestSupport.lines(friday)
        #expect(fridayLines.contains("11:10-11:57 4 lunch Lunch"))
        #expect(fridayLines.contains("09:26-10:38 2+3A classPeriod AP Chemistry"))

        let thursday = timeline(config, on: day(2026, 9, 17))
        let thursdayLines = TestSupport.lines(thursday)
        #expect(thursdayLines.contains("11:10-11:30 4A advisory Advisory"))
        #expect(thursdayLines.contains("11:37-11:57 4B lunch Lunch"))
    }

    // MARK: - spanLabel on ordinary blocks

    @Test func spanLabelsMatchBlockShapes() {
        var config = UserConfig()
        config.lunch = SplitAssignment(basePeriod: 4, choice: .a)
        let t = timeline(config)
        #expect(t.blocks.first { $0.id == "1" }?.spanLabel == nil)
        #expect(t.blocks.first { $0.id == "4A" }?.spanLabel == "4A")
        #expect(t.blocks.first { $0.id == "4B" }?.spanLabel == "4B")
    }
}
