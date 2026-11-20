import Testing
import Foundation
@testable import ScheduleKit

@Suite struct LunchPlacementTests {
    /// Every placement onboarding can offer on an untouched schedule.
    private static let all: [LunchPlacement] = UserConfig.advisoryPeriods.flatMap { period in
        [LunchPlacement(period: period)] + [HalfChoice.a, .b].flatMap { portion in
            LunchPlacement.OtherHalf.allCases.map {
                LunchPlacement(period: period, portion: portion, otherHalf: $0)
            }
        }
    }

    private func config(_ placement: LunchPlacement?) -> UserConfig {
        var config = UserConfig()
        config.setLunchPlacement(placement)
        return config
    }

    @Test func aNewScheduleHasNoPlacement() {
        #expect(UserConfig().lunchPlacement == nil)
    }

    @Test(arguments: all)
    func aPlacementReadsBackAsItWasSet(_ placement: LunchPlacement) {
        #expect(config(placement).lunchPlacement == placement)
    }

    @Test(arguments: all)
    func aSecondPlacementLeavesNoTraceOfTheFirst(_ first: LunchPlacement) {
        for second in Self.all {
            var moved = config(first)
            moved.setLunchPlacement(second)
            #expect(moved == config(second), "\(first) then \(second)")
        }
    }

    @Test(arguments: all)
    func clearingReturnsThePeriodToAPlainClass(_ placement: LunchPlacement) {
        var cleared = config(placement)
        cleared.setLunchPlacement(nil)
        #expect(cleared == UserConfig())
    }

    @Test func aWholePeriodLunchFillsBothHalves() {
        let config = config(LunchPlacement(period: 5))
        #expect(config.plan(for: 5) == PeriodPlan(a: .lunch, b: .lunch))
    }

    @Test func aFreeHalfSitsBesideLunch() {
        let config = config(LunchPlacement(period: 4, portion: .a))
        #expect(config.plan(for: 4) == PeriodPlan(a: .lunch, b: .free))
    }

    @Test func advisoryTakesTheHalfLunchLeaves() {
        let config = config(LunchPlacement(period: 6, portion: .b, otherHalf: .advisory))
        #expect(config.plan(for: 6) == PeriodPlan(a: .advisory, b: .lunch))
    }

    @Test func theClassBeforeABLunchRunsLongIntoIt() {
        let config = config(LunchPlacement(period: 5, portion: .b, otherHalf: .neighborClass))
        #expect(config.classLength(anchor: 4) == .extendsForward)
        let blocks = standardTemplate(config: config, catalog: TestSupport.catalog)
        #expect(blocks.map(\.id).contains("4+5A"))
        #expect(blocks.first { $0.role == .lunch }?.half == .b)
    }

    @Test func theClassAfterAnALunchStartsEarlyInIt() {
        let config = config(LunchPlacement(period: 5, portion: .a, otherHalf: .neighborClass))
        #expect(config.classLength(anchor: 6) == .startsEarly)
        #expect(config.plan(for: 5) == PeriodPlan(a: .lunch, b: .classSlot(anchor: 6)))
    }

    @Test func aNeighbourWithNoClassLeavesTheHalfFree() {
        var config = UserConfig()
        config.freePeriods = [4]
        let placement = LunchPlacement(period: 5, portion: .b, otherHalf: .neighborClass)
        #expect(!config.neighborClassCanFill(placement))
        config.setLunchPlacement(placement)
        #expect(config.plan(for: 5) == PeriodPlan(a: .free, b: .lunch))
        #expect(config.freePeriods == [4])
    }

    @Test func theCurrentLunchPeriodCanBecomeTheNeighbour() {
        var config = config(LunchPlacement(period: 5))
        let placement = LunchPlacement(period: 4, portion: .a, otherHalf: .neighborClass)
        #expect(config.neighborClassCanFill(placement))
        config.setLunchPlacement(placement)
        #expect(config.plan(for: 4) == PeriodPlan(a: .lunch, b: .classSlot(anchor: 5)))
        #expect(config.plan(for: 5) == .standardClass(5))
    }

    @Test func aWholePeriodLunchHasNoNeighbourToExtend() {
        #expect(!UserConfig().neighborClassCanFill(LunchPlacement(period: 5)))
    }

    @Test func aLongClassAnchoredInTheLunchPeriodLetsGoOfItsExtraHalf() {
        var config = UserConfig()
        config.setClassLength(anchor: 5, .extendsForward)
        config.setLunchPlacement(LunchPlacement(period: 5, portion: .b))
        #expect(config.plan(for: 6).a != .classSlot(anchor: 5))
    }

    @Test func aLeftoverHalfOfThePeriodsOwnClassReadsAsFree() {
        var config = UserConfig()
        config.lunch = SplitAssignment(basePeriod: 5, choice: .b)
        #expect(config.plan(for: 5).a == .classSlot(anchor: 5))
        #expect(config.lunchPlacement == LunchPlacement(period: 5, portion: .b, otherHalf: .free))
    }

    @Test func aPlacementOutsideTheLunchPeriodsOnlyClears() {
        var config = config(LunchPlacement(period: 5))
        config.setLunchPlacement(LunchPlacement(period: 2))
        #expect(config.lunch == nil)
        #expect(config == UserConfig())
    }

    @Test func classDetailsAndOtherPeriodsSurviveAMove() {
        var config = UserConfig()
        config.customizations["4"] = PeriodCustomization(name: "AP Biology", room: "2216")
        config.freePeriods = [8]
        config.setLunchPlacement(LunchPlacement(period: 5, portion: .b, otherHalf: .neighborClass))
        config.setLunchPlacement(LunchPlacement(period: 6))
        #expect(config.customizations["4"] == PeriodCustomization(name: "AP Biology", room: "2216"))
        #expect(config.freePeriods == [8])
        #expect(config.classLength(anchor: 4) == .standard)
    }
}
