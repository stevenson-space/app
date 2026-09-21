import Testing
@testable import ScheduleKit

@Suite struct HalfPeriodDisplayTests {
    let monday = day(2026, 9, 14)

    @Test func usesOfficialBellsAndPreservesPersonalization() throws {
        var config = UserConfig()
        config.customizations["2"] = PeriodCustomization(name: "Chemistry", room: "118")
        config.setClassExtended(anchor: 2, true)
        config.lunch = SplitAssignment(basePeriod: 3, choice: .b)
        let timeline = resolveDay(monday, inputs: TestSupport.inputs(config: config))
        let rows = timeline.halfPeriodBlocks(catalog: TestSupport.catalog)
        let chemistry = rows.filter { $0.displayName == "Chemistry" }
        #expect(chemistry.map(\.id) == ["2A", "2B", "3A"])
        #expect(chemistry.allSatisfy { $0.room == "118" && $0.customizationID == .period(2) })
        let first = try #require(rows.first { $0.id == "1A" })
        let second = try #require(rows.first { $0.id == "1B" })
        #expect(first.end == TestSupport.at(monday, 8, 54))
        #expect(second.start == TestSupport.at(monday, 9, 1))
        #expect(rows.first { $0.id == "3B" }?.role == .lunch)
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(timeline.moments.contains { $0.id == "2+3A" })
    }

    @Test func preservesFridayLunchAndFreeHalves() {
        var config = UserConfig()
        config.setPairedAdvisory(basePeriod: 4, advisoryHalf: .a)
        config.setSlot(period: 8, half: .b, to: .free)
        let friday = resolveDay(day(2026, 9, 18), inputs: TestSupport.inputs(config: config))
        let rows = friday.halfPeriodBlocks(catalog: TestSupport.catalog)
        #expect(rows.filter { $0.periodID == .period(4) }.map(\.role) == [.lunch, .lunch])
        #expect(rows.first { $0.id == "8B" }?.role == .free)
    }

    @Test(arguments: BellFamily.allCases)
    func respectsEachScheduleFamily(_ family: BellFamily) throws {
        let override = DayOverride(day: monday, type: .bell(family: family, rotation: nil))
        let timeline = resolveDay(monday, inputs: TestSupport.inputs(overrides: [monday: override]))
        let schedule = try #require(TestSupport.catalog.schedule(family: family, rotation: nil))
        let rows = timeline.halfPeriodBlocks(catalog: TestSupport.catalog)
        if schedule.hasABVariants {
            #expect(rows.filter { $0.half != nil }.count == schedule.abBlocks.count)
            #expect(rows.filter { $0.periodID.periodNumber == nil } ==
                    timeline.blocks.filter { $0.periodID.periodNumber == nil })
        } else {
            #expect(rows == timeline.blocks)
        }
    }

    @Test func nonSchoolDayStaysEmpty() {
        let timeline = resolveDay(day(2026, 9, 19), inputs: TestSupport.inputs())
        #expect(timeline.halfPeriodBlocks(catalog: TestSupport.catalog).isEmpty)
    }
}
