import Testing
import Foundation
@testable import ScheduleKit

@Suite struct BellCatalogTests {
    let catalog: BellScheduleCatalog

    init() throws {
        catalog = try BellScheduleCatalog.loadBundled()
    }

    @Test func allEightTablesPresent() {
        let ids = Set(catalog.all.map(\.id))
        #expect(ids == ["standard", "lateArrival", "odyssey", "activityPeriod",
                        "pmAssembly", "earlyDismissal1", "earlyDismissal2", "summer"])
    }

    @Test func standardShape() throws {
        let standard = try #require(catalog.schedule(family: .standard))
        #expect(standard.fullBlocks.map(\.id) == (1...8).map(PeriodID.period))
        #expect(standard.fullBlocks.first?.start == HourMinute(hour: 8, minute: 30))
        #expect(standard.fullBlocks.last?.end == HourMinute(hour: 15, minute: 25))
        #expect(standard.abBlocks.count == 16)

        let fourth = standard.abBlocks(forPeriod: 4)
        #expect(fourth.count == 2)
        #expect(fourth[0].half == .a)
        #expect(fourth[0].start == HourMinute(hour: 11, minute: 10))
        #expect(fourth[0].end == HourMinute(hour: 11, minute: 30))
        #expect(fourth[1].half == .b)
        #expect(fourth[1].start == HourMinute(hour: 11, minute: 37))
        #expect(fourth[1].end == HourMinute(hour: 11, minute: 57))
    }

    @Test func abVariantAvailabilityMatchesSpec() {
        for schedule in catalog.all {
            let expectAB = ["standard", "activityPeriod", "pmAssembly"].contains(schedule.id)
            #expect(schedule.hasABVariants == expectAB, "\(schedule.id)")
        }
    }

    @Test func earlyDismissalRotationsRunOutOfOrder() throws {
        let r1 = try #require(catalog.schedule(family: .earlyDismissal, rotation: .rotation1))
        let r2 = try #require(catalog.schedule(family: .earlyDismissal, rotation: .rotation2))
        #expect(r1.fullBlocks.map(\.id) == [.period(6), .period(2), .period(3), .period(4), .makeup])
        #expect(r2.fullBlocks.map(\.id) == [.period(5), .period(1), .period(7), .period(8), .makeup])

        // Makeup begins the second the preceding period ends (zero-length gap).
        for schedule in [r1, r2] {
            let fourth = schedule.fullBlocks[3]
            let makeup = schedule.fullBlocks[4]
            #expect(makeup.start == fourth.end)
        }
    }

    @Test func earlyDismissalDefaultsToRotation1() throws {
        let defaulted = try #require(catalog.schedule(family: .earlyDismissal))
        #expect(defaulted.rotation == .rotation1)
    }

    @Test func odysseyStartsWithHomeroom() throws {
        let odyssey = try #require(catalog.schedule(family: .odyssey))
        #expect(odyssey.fullBlocks.first?.id == .homeroom)
        #expect(odyssey.fullBlocks.first?.start == HourMinute(hour: 10, minute: 15))
        #expect(odyssey.fullBlocks.map(\.id).dropFirst() == (1...5).map(PeriodID.period)[...])
    }

    @Test func summerIsOneLongBlock() throws {
        let summer = try #require(catalog.schedule(family: .summer))
        #expect(summer.fullBlocks == [
            Block(id: .summer, start: HourMinute(hour: 7, minute: 45), end: HourMinute(hour: 12, minute: 50))
        ])
    }

    @Test func abHalvesAlwaysLeaveAnIntraPeriodGap() {
        for schedule in catalog.all where schedule.hasABVariants {
            for number in 1...8 {
                let halves = schedule.abBlocks(forPeriod: number)
                guard halves.count == 2 else { continue }
                #expect(halves[0].end < halves[1].start, "\(schedule.id) period \(number)")
            }
        }
    }

    @Test func rejectsOverlappingBlocks() {
        let bad = """
        {"schedules":[{"id":"x","family":"standard","displayName":"X",
        "fullBlocks":[{"period":"1","start":"8:30","end":"9:21"},
                      {"period":"2","start":"9:00","end":"10:13"}]}]}
        """
        #expect(throws: CatalogError.self) {
            _ = try BellScheduleCatalog(data: Data(bad.utf8))
        }
    }

    @Test func rejectsHalvesThatDontTileParent() {
        let bad = """
        {"schedules":[{"id":"x","family":"standard","displayName":"X",
        "fullBlocks":[{"period":"1","start":"8:30","end":"9:21"}],
        "abBlocks":[{"period":"1","half":"A","start":"8:31","end":"8:54"},
                    {"period":"1","half":"B","start":"9:01","end":"9:21"}]}]}
        """
        #expect(throws: CatalogError.self) {
            _ = try BellScheduleCatalog(data: Data(bad.utf8))
        }
    }
}
