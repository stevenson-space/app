import Testing
import Foundation
@testable import ScheduleKit

@Suite struct PeriodPlanTests {
    // MARK: - HalfSlotAssignment coding

    @Test func slotAssignmentEncodesAsStrings() throws {
        let encoder = JSONEncoder()
        func encoded(_ slot: HalfSlotAssignment) throws -> String {
            String(decoding: try encoder.encode([slot]), as: UTF8.self)
        }
        #expect(try encoded(.lunch) == #"["lunch"]"#)
        #expect(try encoded(.advisory) == #"["advisory"]"#)
        #expect(try encoded(.free) == #"["free"]"#)
        #expect(try encoded(.classSlot(anchor: 4)) == #"["class:4"]"#)
    }

    @Test func slotAssignmentRoundTrips() throws {
        let all: [HalfSlotAssignment] = [.lunch, .advisory, .free,
                                         .classSlot(anchor: 1), .classSlot(anchor: 8)]
        let data = try JSONEncoder().encode(all)
        let back = try JSONDecoder().decode([HalfSlotAssignment].self, from: data)
        #expect(back == all)
    }

    @Test func unknownSlotStringThrows() {
        // Unknown kinds must throw so UserConfig can fall back to the legacy
        // fields a future app version also writes.
        let data = Data(#"["study-hall"]"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode([HalfSlotAssignment].self, from: data)
        }
    }

    @Test func malformedClassAnchorThrows() {
        let data = Data(#"["class:x"]"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode([HalfSlotAssignment].self, from: data)
        }
    }

    // MARK: - PeriodPlan

    @Test func standardClassPlanIsUniformOwnClass() {
        let plan = PeriodPlan.standardClass(3)
        #expect(plan.a == .classSlot(anchor: 3))
        #expect(plan.b == .classSlot(anchor: 3))
        #expect(plan.isUniform)
        #expect(plan.isStandardClass(for: 3))
        #expect(!plan.isStandardClass(for: 4))
    }

    @Test func slotAccessorsReadAndWriteHalves() {
        var plan = PeriodPlan.standardClass(5)
        plan.setSlot(.a, .lunch)
        #expect(plan.slot(.a) == .lunch)
        #expect(plan.slot(.b) == .classSlot(anchor: 5))
        #expect(!plan.isUniform)
    }
}

@Suite struct UserConfigGridTests {
    private func decode(_ json: String) throws -> UserConfig {
        try JSONDecoder().decode(UserConfig.self, from: Data(json.utf8))
    }

    // MARK: - Legacy blob migration

    @Test func legacyLunchHalfBlobMigratesToGrid() throws {
        let config = try decode(#"{"lunch":{"basePeriod":4,"choice":"A"}}"#)
        #expect(config.plan(for: 4) == PeriodPlan(a: .lunch, b: .classSlot(anchor: 4)))
        #expect(config.plan(for: 5) == .standardClass(5))
        #expect(config.lunch == SplitAssignment(basePeriod: 4, choice: .a))
    }

    @Test func legacyFullLunchAndFreePeriodsMigrate() throws {
        let config = try decode(#"{"lunch":{"basePeriod":5,"choice":"full"},"freePeriods":[7]}"#)
        #expect(config.plan(for: 5) == PeriodPlan(a: .lunch, b: .lunch))
        #expect(config.plan(for: 7) == PeriodPlan(a: .free, b: .free))
        #expect(config.lunch == SplitAssignment(basePeriod: 5, choice: .full))
        #expect(config.freePeriods == [7])
    }

    @Test func legacyAdvisoryPairMigrates() throws {
        let config = try decode(
            #"{"advisory":{"basePeriod":4,"choice":"A"},"lunch":{"basePeriod":4,"choice":"B"}}"#)
        #expect(config.plan(for: 4) == PeriodPlan(a: .advisory, b: .lunch))
        #expect(config.advisory == SplitAssignment(basePeriod: 4, choice: .a))
        #expect(config.lunch == SplitAssignment(basePeriod: 4, choice: .b))
    }

    @Test func legacySameHalfConflictLetsLunchWin() throws {
        let config = try decode(
            #"{"advisory":{"basePeriod":4,"choice":"A"},"lunch":{"basePeriod":4,"choice":"A"}}"#)
        #expect(config.plan(for: 4) == PeriodPlan(a: .lunch, b: .classSlot(anchor: 4)))
        #expect(config.advisory == nil)
    }

    @Test func legacyFreePeriodWithLunchHalfKeepsOtherHalfFree() throws {
        // Legacy semantics: period 4 in freePeriods + lunch 4A rendered 4B free.
        let config = try decode(
            #"{"lunch":{"basePeriod":4,"choice":"A"},"freePeriods":[4]}"#)
        #expect(config.plan(for: 4) == PeriodPlan(a: .lunch, b: .free))
    }

    @Test func gridWinsOverLegacyFieldsWhenPresent() throws {
        let config = try decode(
            #"{"lunch":{"basePeriod":4,"choice":"A"},"periodPlans":{"5":{"a":"lunch","b":"class:5"}}}"#)
        #expect(config.lunch == SplitAssignment(basePeriod: 5, choice: .a))
        #expect(config.plan(for: 4) == .standardClass(4))
    }

    @Test func unknownSlotKindInPlansFallsBackToLegacyFields() throws {
        let config = try decode(
            #"{"lunch":{"basePeriod":6,"choice":"B"},"periodPlans":{"5":{"a":"nap","b":"class:5"}}}"#)
        #expect(config.lunch == SplitAssignment(basePeriod: 6, choice: .b))
        #expect(config.plan(for: 5) == .standardClass(5))
    }

    @Test func outOfRangePlanKeysAreDropped() throws {
        let config = try decode(#"{"periodPlans":{"9":{"a":"lunch","b":"lunch"},"4":{"a":"lunch","b":"lunch"}}}"#)
        #expect(Set(config.periodPlans.keys) == [4])
        #expect(config.lunch == SplitAssignment(basePeriod: 4, choice: .full))
    }

    @Test func encodingWritesGridAndDerivedLegacyFields() throws {
        var config = UserConfig()
        config.lunch = SplitAssignment(basePeriod: 4, choice: .a)
        config.setClassExtended(anchor: 2, true)

        let data = try JSONEncoder().encode(config)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["periodPlans"] != nil)
        let lunch = try #require(object["lunch"] as? [String: Any])
        #expect(lunch["basePeriod"] as? Int == 4)
        #expect(lunch["choice"] as? String == "A")

        let back = try JSONDecoder().decode(UserConfig.self, from: data)
        #expect(back == config)
    }

    // MARK: - Derived accessors

    @Test func settingLunchClearsThePreviousSlot() {
        var config = UserConfig()
        config.lunch = SplitAssignment(basePeriod: 4, choice: .a)
        config.lunch = SplitAssignment(basePeriod: 5, choice: .full)
        #expect(config.plan(for: 4) == .standardClass(4))
        #expect(config.plan(for: 5) == PeriodPlan(a: .lunch, b: .lunch))

        config.lunch = nil
        #expect(config.plan(for: 5) == .standardClass(5))
        #expect(config.lunch == nil)
    }

    @Test func clearingLunchDoesNotDisturbOtherAssignments() {
        var config = UserConfig()
        config.setSlot(period: 3, half: .a, to: .classSlot(anchor: 2))
        config.lunch = SplitAssignment(basePeriod: 3, choice: .b)
        config.lunch = nil
        // The class tail in 3A is untouched; the vacated half goes free
        // rather than resurrecting a phantom "3rd Period" half class.
        #expect(config.plan(for: 3) == PeriodPlan(a: .classSlot(anchor: 2), b: .free))
    }

    @Test func movingAHalfLunchFreesTheVacatedHalf() {
        var config = UserConfig()
        config.setClassExtended(anchor: 3, true) // physics 3 + 4A
        config.lunch = SplitAssignment(basePeriod: 4, choice: .b)
        config.lunch = SplitAssignment(basePeriod: 5, choice: .full)
        #expect(config.plan(for: 4) == PeriodPlan(a: .classSlot(anchor: 3), b: .free))
        // A vacated half next to its own class restores the full class.
        var simple = UserConfig()
        simple.lunch = SplitAssignment(basePeriod: 4, choice: .a)
        simple.lunch = SplitAssignment(basePeriod: 5, choice: .full)
        #expect(simple.plan(for: 4) == .standardClass(4))
    }

    @Test func freePeriodsSetterDiffApplies() {
        var config = UserConfig()
        config.freePeriods = [6, 7]
        #expect(config.plan(for: 6) == PeriodPlan(a: .free, b: .free))
        config.freePeriods = [7]
        #expect(config.plan(for: 6) == .standardClass(6))
        #expect(config.plan(for: 7) == PeriodPlan(a: .free, b: .free))
        config.freePeriods.remove(7)
        #expect(config.periodPlans.isEmpty)
    }

    // MARK: - Class extension helpers

    @Test func extendingAClassPaintsTheNextPeriodsFirstHalf() {
        var config = UserConfig()
        config.setClassExtended(anchor: 2, true)
        #expect(config.plan(for: 3) == PeriodPlan(a: .classSlot(anchor: 2), b: .classSlot(anchor: 3)))
        config.setClassExtended(anchor: 2, false)
        #expect(config.plan(for: 3) == .standardClass(3))
    }

    @Test func retractingLeavesForeignAssignmentsAlone() {
        var config = UserConfig()
        config.setSlot(period: 3, half: .a, to: .lunch)
        config.setClassExtended(anchor: 2, false)
        #expect(config.plan(for: 3).a == .lunch)
    }

    @Test func extendingOutOfRangeIsIgnored() {
        var config = UserConfig()
        config.setClassExtended(anchor: 8, true) // no period 9 to extend into
        config.setClassExtended(anchor: 0, true)
        #expect(config.periodPlans.isEmpty)
    }

    // MARK: - Class length transitions

    @Test func extendingViaClassLengthDisplacesTheNextOwnClass() {
        var config = UserConfig()
        config.setClassLength(anchor: 2, .extendsForward)
        #expect(config.classLength(anchor: 2) == .extendsForward)
        #expect(config.plan(for: 3) == PeriodPlan(a: .classSlot(anchor: 2), b: .free))
    }

    @Test func retractingAClassExpandsItsLeftoverLunchToTheFullPeriod() {
        // The user's flow: physics 3–4A with lunch 4B, then back to 1 period —
        // lunch takes the whole period, ready for the advisory toggle.
        var config = UserConfig()
        config.setClassLength(anchor: 3, .extendsForward)
        config.lunch = SplitAssignment(basePeriod: 4, choice: .b)
        #expect(config.plan(for: 4) == PeriodPlan(a: .classSlot(anchor: 3), b: .lunch))

        config.setClassLength(anchor: 3, .standard)
        #expect(config.plan(for: 3) == .standardClass(3))
        #expect(config.plan(for: 4) == PeriodPlan(a: .lunch, b: .lunch))
        #expect(config.lunch == SplitAssignment(basePeriod: 4, choice: .full))
    }

    @Test func extendingIntoAFullLunchShrinksLunchToTheOtherHalf() {
        // The blocked round trip: physics 1 period + full lunch 4 must be
        // able to become physics 3–4A + lunch 4B again.
        var config = UserConfig()
        config.lunch = SplitAssignment(basePeriod: 4, choice: .full)
        config.setClassLength(anchor: 3, .extendsForward)
        #expect(config.plan(for: 4) == PeriodPlan(a: .classSlot(anchor: 3), b: .lunch))
        #expect(config.lunch == SplitAssignment(basePeriod: 4, choice: .b))

        config.setClassLength(anchor: 3, .standard)
        #expect(config.plan(for: 4) == PeriodPlan(a: .lunch, b: .lunch))
    }

    @Test func startingEarlyIntoAFullLunchShrinksLunchToTheFirstHalf() {
        var config = UserConfig()
        config.lunch = SplitAssignment(basePeriod: 3, choice: .full)
        config.setClassLength(anchor: 4, .startsEarly)
        #expect(config.plan(for: 3) == PeriodPlan(a: .lunch, b: .classSlot(anchor: 4)))
        #expect(config.lunch == SplitAssignment(basePeriod: 3, choice: .a))
    }

    @Test func extendingNeverDisplacesAHalfLunchOrAdvisory() {
        // Lunch exactly in the claimed half: refuse (the UI blocks it too).
        var config = UserConfig()
        config.lunch = SplitAssignment(basePeriod: 4, choice: .a)
        config.setClassLength(anchor: 3, .extendsForward)
        #expect(config.plan(for: 4).a == .lunch)
        #expect(config.classLength(anchor: 3) == .standard)

        var freshman = UserConfig()
        freshman.setPairedAdvisory(basePeriod: 4, advisoryHalf: .a)
        freshman.setClassLength(anchor: 3, .extendsForward)
        #expect(freshman.plan(for: 4).a == .advisory)
        #expect(freshman.classLength(anchor: 3) == .standard)
    }

    @Test func retractingAClassWithFreeLeftoverRestoresTheFullClass() {
        var config = UserConfig()
        config.setClassLength(anchor: 3, .extendsForward)
        config.setClassLength(anchor: 3, .standard)
        #expect(config.periodPlans.isEmpty)
    }

    @Test func retractingABackwardClassExpandsAdjacentHalfLunch() {
        var config = UserConfig()
        config.lunch = SplitAssignment(basePeriod: 3, choice: .a)
        config.setClassLength(anchor: 4, .startsEarly) // class = 3B + 4
        #expect(config.plan(for: 3) == PeriodPlan(a: .lunch, b: .classSlot(anchor: 4)))

        config.setClassLength(anchor: 4, .standard)
        #expect(config.plan(for: 3) == PeriodPlan(a: .lunch, b: .lunch))
        #expect(config.lunch == SplitAssignment(basePeriod: 3, choice: .full))
    }

    @Test func advisoryToggleSequencesKeepLunchIntact() {
        // ON from a full-period lunch: the pair splits the period.
        var config = UserConfig()
        config.lunch = SplitAssignment(basePeriod: 4, choice: .full)
        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .a)
        #expect(config.plan(for: 4) == PeriodPlan(a: .advisory, b: .lunch))

        // Flipping the advisory half swaps the pair cleanly.
        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .b)
        #expect(config.plan(for: 4) == PeriodPlan(a: .lunch, b: .advisory))

        // OFF (the UI path): the advisory half goes free, lunch stays put.
        config.setSlot(period: 4, half: .b, to: .free)
        #expect(config.plan(for: 4) == PeriodPlan(a: .lunch, b: .free))
        #expect(config.advisory == nil)
        #expect(config.lunch == SplitAssignment(basePeriod: 4, choice: .a))
    }

    // MARK: - Backward extension helper

    @Test func startsEarlyClaimsThePreviousBHalf() {
        var config = UserConfig()
        config.setSlot(period: 3, half: .b, to: .free)
        config.setClassStartsEarly(anchor: 4, true)
        #expect(config.plan(for: 3).b == .classSlot(anchor: 4))
        config.setClassStartsEarly(anchor: 4, false)
        #expect(config.plan(for: 3).b == .free)
    }

    @Test func startsEarlyOnAFullClassNeighborFreesItsFirstHalf() {
        // Claiming 3B out of a full period-3 class must not leave 3A as a
        // phantom half class — the neighbor's class is fully displaced.
        var config = UserConfig()
        config.setClassStartsEarly(anchor: 4, true)
        #expect(config.plan(for: 3) == PeriodPlan(a: .free, b: .classSlot(anchor: 4)))
    }

    @Test func displacingAClassAlsoRetractsItsOwnClaims() {
        // Period 3's class was 1½ (2B+3). Period 4's class then claims 3B,
        // displacing period 3's class — its old 2B claim must not dangle.
        var config = UserConfig()
        config.setClassStartsEarly(anchor: 3, true) // 2B ← class 3
        config.setClassStartsEarly(anchor: 4, true) // displaces class 3
        #expect(config.plan(for: 2).b == .free)
        #expect(config.plan(for: 3) == PeriodPlan(a: .free, b: .classSlot(anchor: 4)))
    }

    @Test func displacedClassClaimInOurOwnPeriodJoinsOurClass() {
        // Class 3 ran 3–4A. Class 4 then starts early in 3B: class 3 is
        // displaced, and its old 4A claim becomes part of class 4 — one
        // contiguous 3B–4 span, not a free hole inside it.
        var config = UserConfig()
        config.setClassExtended(anchor: 3, true) // 4A ← class 3
        config.setClassStartsEarly(anchor: 4, true)
        #expect(config.plan(for: 3) == PeriodPlan(a: .free, b: .classSlot(anchor: 4)))
        #expect(config.plan(for: 4) == .standardClass(4))
    }

    @Test func startsEarlyRefusesToDisplaceLunchOrAdvisory() {
        var config = UserConfig()
        config.lunch = SplitAssignment(basePeriod: 3, choice: .b)
        config.setClassStartsEarly(anchor: 4, true)
        #expect(config.plan(for: 3).b == .lunch)
    }

    @Test func retractingStartsEarlyLeavesAFullyFreePeriodUniform() {
        var config = UserConfig()
        config.setClassStartsEarly(anchor: 4, true) // 3 becomes (free, class:4)
        config.setClassStartsEarly(anchor: 4, false)
        #expect(config.plan(for: 3) == PeriodPlan(a: .free, b: .free))
        #expect(config.freePeriods.contains(3))
    }

    // MARK: - Claim retraction on type changes

    @Test func retractClassClaimsFreesAdjacentHalves() {
        var config = UserConfig()
        config.setClassExtended(anchor: 2, true)   // 3A ← class 2
        config.retractClassClaims(anchor: 2)
        #expect(config.plan(for: 3).a == .free)

        var backward = UserConfig()
        backward.setClassStartsEarly(anchor: 4, true) // 3B ← class 4
        backward.retractClassClaims(anchor: 4)
        #expect(backward.plan(for: 3).b == .free)
        // Slots not pointing at the anchor stay untouched.
        #expect(backward.plan(for: 5) == .standardClass(5))
    }

    // MARK: - Emoji customization survives coding

    @Test func customizationEmojiRoundTripsAndOldBlobsDecode() throws {
        var config = UserConfig()
        config.customizations["2"] = PeriodCustomization(name: "AP Chemistry", room: "118", emoji: "🧪")
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(UserConfig.self, from: data)
        #expect(back.customizations["2"]?.emoji == "🧪")

        // Blob written before the emoji field existed.
        let legacy = #"{"customizations":{"2":{"name":"AP Chemistry","room":"118"}}}"#
        let old = try JSONDecoder().decode(UserConfig.self, from: Data(legacy.utf8))
        #expect(old.customizations["2"]?.emoji == nil)
        #expect(old.customizations["2"]?.name == "AP Chemistry")
    }
}

@Suite struct StandardTemplateTests {
    @Test func templateShowsMergedSpansOnTheStandardBellTable() {
        var config = UserConfig()
        config.customizations["2"] = PeriodCustomization(name: "AP Chemistry")
        config.setClassExtended(anchor: 2, true)
        config.lunch = SplitAssignment(basePeriod: 3, choice: .b)

        let blocks = standardTemplate(config: config, catalog: TestSupport.catalog)
        let ids = blocks.map(\.id)
        #expect(ids.contains("2+3A"))
        #expect(ids.contains("3B"))
        #expect(blocks.first { $0.id == "2+3A" }?.displayName == "AP Chemistry")
        // Advisory is not Friday-collapsed in the template.
        var freshman = UserConfig()
        freshman.setPairedAdvisory(basePeriod: 4, advisoryHalf: .a)
        let freshmanIDs = standardTemplate(config: freshman, catalog: TestSupport.catalog).map(\.id)
        #expect(freshmanIDs.contains("4A"))
        #expect(freshmanIDs.contains("4B"))
    }
}
