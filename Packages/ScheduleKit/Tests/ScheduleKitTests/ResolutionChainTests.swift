import Testing
import Foundation
@testable import ScheduleKit

@Suite struct ResolutionChainTests {
    @Test func unlistedInSessionWeekdayIsStandardByDesign() {
        let timeline = resolveDay(day(2026, 9, 15), inputs: TestSupport.inputs())
        #expect(timeline.kind == .school)
        #expect(timeline.family == .standard)
        #expect(timeline.provenance == .defaultStandard)
        #expect(timeline.blocks.count == 8)
    }

    @Test func orientationDayIsStandardWithNote() {
        let timeline = resolveDay(day(2026, 8, 12), inputs: TestSupport.inputs())
        #expect(timeline.family == .standard)
        #expect(timeline.dayNote == "Freshman Orientation")
    }

    @Test func mapEntryBeatsDefault() throws {
        let map = try TestSupport.map(#"{"Late Arrival": ["9/18/2026"]}"#)
        let timeline = resolveDay(day(2026, 9, 18), inputs: TestSupport.inputs(map: map))
        #expect(timeline.family == .lateArrival)
        #expect(timeline.provenance == .remoteMap)
        #expect(timeline.blocks.first?.start == TestSupport.at(day(2026, 9, 18), 10, 30))
    }

    @Test func overrideBeatsMap() throws {
        let map = try TestSupport.map(#"{"Late Arrival": ["9/18/2026"]}"#)
        let overrides = [day(2026, 9, 18): DayOverride(
            day: day(2026, 9, 18), type: .bell(family: .standard, rotation: nil))]
        let timeline = resolveDay(day(2026, 9, 18),
                                  inputs: TestSupport.inputs(map: map, overrides: overrides))
        #expect(timeline.family == .standard)
        #expect(timeline.provenance == .override)
    }

    @Test func overrideToNoSchoolAndAsync() {
        let target = day(2026, 10, 5)
        let noSchool = resolveDay(target, inputs: TestSupport.inputs(
            overrides: [target: DayOverride(day: target, type: .noSchool)]))
        #expect(noSchool.kind == .noSchool)
        #expect(noSchool.provenance == .override)

        let async = resolveDay(target, inputs: TestSupport.inputs(
            overrides: [target: DayOverride(day: target, type: .asynchronous)]))
        #expect(async.kind == .asynchronous)
        #expect(async.blocks.isEmpty)
    }

    @Test func mapBeatsBundledBreak() throws {
        // 12/22/2026 is inside winter break; a map entry still wins.
        let map = try TestSupport.map(#"{"Late Arrival": ["12/22/2026"]}"#)
        let timeline = resolveDay(day(2026, 12, 22), inputs: TestSupport.inputs(map: map))
        #expect(timeline.family == .lateArrival)
    }

    @Test func bundledBreaksBeatWeekdayDefaultAndWeekend() {
        let breakWeekday = resolveDay(day(2026, 12, 23), inputs: TestSupport.inputs())
        #expect(breakWeekday.kind == .breakDay(label: "Winter Break"))
        #expect(breakWeekday.provenance == .bundledBreak)

        // A Saturday inside the break reads "Winter Break", not "Weekend".
        let breakSaturday = resolveDay(day(2026, 12, 26), inputs: TestSupport.inputs())
        #expect(breakSaturday.kind == .breakDay(label: "Winter Break"))

        let spring = resolveDay(day(2027, 3, 24), inputs: TestSupport.inputs())
        #expect(spring.kind == .breakDay(label: "Spring Break"))
    }

    @Test func weekendsInSession() {
        let saturday = resolveDay(day(2026, 9, 19), inputs: TestSupport.inputs())
        #expect(saturday.kind == .weekend)
        let sunday = resolveDay(day(2026, 9, 20), inputs: TestSupport.inputs())
        #expect(sunday.kind == .weekend)
    }

    @Test func outsideYearNeverDefaultsToStandard() {
        #expect(resolveDay(day(2026, 7, 30), inputs: TestSupport.inputs()).kind == .outsideYear)
        #expect(resolveDay(day(2027, 6, 1), inputs: TestSupport.inputs()).kind == .outsideYear)
        #expect(resolveDay(day(2027, 5, 27), inputs: TestSupport.inputs()).kind == .outsideYear)
        // Last day of school is still in session.
        #expect(resolveDay(day(2027, 5, 26), inputs: TestSupport.inputs()).kind == .school)
    }

    @Test func mapWinsOutsideYearBounds() throws {
        let map = try TestSupport.map(#"{"Summer School": ["6/15/2027"]}"#)
        let timeline = resolveDay(day(2027, 6, 15), inputs: TestSupport.inputs(map: map))
        #expect(timeline.kind == .school)
        #expect(timeline.family == .summer)
        #expect(timeline.blocks.map(\.id) == ["summer"])
    }

    @Test func mapWinsOverWeekend() throws {
        let map = try TestSupport.map(#"{"PM Assembly": ["9/19/2026"]}"#)
        let timeline = resolveDay(day(2026, 9, 19), inputs: TestSupport.inputs(map: map))
        #expect(timeline.kind == .school)
        #expect(timeline.family == .pmAssembly)
    }

    @Test func asyncDayFromMap() throws {
        let map = try TestSupport.map(#"{"Asynchronous": ["11/13/2026"]}"#)
        let timeline = resolveDay(day(2026, 11, 13), inputs: TestSupport.inputs(map: map))
        #expect(timeline.kind == .asynchronous)
        #expect(timeline.scheduleLabel == "Asynchronous E-Learning Day")
        #expect(timeline.blocks.isEmpty)
        #expect(timeline.moments.isEmpty)
    }

    @Test func unknownTypeDegradedHonestly() throws {
        let map = try TestSupport.map(#"{"Wacky Hat Day": ["10/6/2026"]}"#)
        let timeline = resolveDay(day(2026, 10, 6), inputs: TestSupport.inputs(map: map))
        #expect(timeline.kind == .unknownType(name: "Wacky Hat Day"))
        #expect(timeline.scheduleLabel == "Wacky Hat Day")
        #expect(timeline.blocks.isEmpty)
    }
}

@Suite struct EDRotationInferenceTests {
    @Test func twoDayRangeInfersBothRotations() throws {
        // Thu 12/17/2026 + Fri 12/18/2026.
        let map = try TestSupport.map(#"{"Early Dismissal": ["12/17/2026-12/18/2026"]}"#)

        let dayOne = resolveDay(day(2026, 12, 17), inputs: TestSupport.inputs(map: map))
        #expect(dayOne.rotation == .rotation1)
        #expect(!dayOne.rotationUncertain)
        #expect(dayOne.blocks.map(\.id) == ["6", "2", "3", "4", "makeup"])
        #expect(dayOne.dayNote == "Finals Day 1")

        let dayTwo = resolveDay(day(2026, 12, 18), inputs: TestSupport.inputs(map: map))
        #expect(dayTwo.rotation == .rotation2)
        #expect(!dayTwo.rotationUncertain)
        #expect(dayTwo.blocks.map(\.id) == ["5", "1", "7", "8", "makeup"])
    }

    @Test func rangeCrossingAWeekendCountsSchoolDaysOnly() throws {
        // Fri 12/18/2026, weekend, Mon 12/21/2026.
        let map = try TestSupport.map(#"{"Early Dismissal": ["12/18/2026-12/21/2026"]}"#)
        let friday = resolveDay(day(2026, 12, 18), inputs: TestSupport.inputs(map: map))
        #expect(friday.rotation == .rotation1)
        #expect(!friday.rotationUncertain)

        let monday = resolveDay(day(2026, 12, 21), inputs: TestSupport.inputs(map: map))
        #expect(monday.rotation == .rotation2)
        #expect(!monday.rotationUncertain)
    }

    @Test func standaloneDateIsUncertainRotation1() throws {
        let map = try TestSupport.map(#"{"Early Dismissal": ["12/17/2026"]}"#)
        let timeline = resolveDay(day(2026, 12, 17), inputs: TestSupport.inputs(map: map))
        #expect(timeline.rotation == .rotation1)
        #expect(timeline.rotationUncertain)
    }

    @Test func deepOrdinalsAlternateButFlagUncertain() throws {
        // Mon 12/14/2026 through Thu 12/17/2026.
        let map = try TestSupport.map(#"{"Early Dismissal": ["12/14/2026-12/17/2026"]}"#)
        let expectations: [(DayKey, EDRotation, Bool)] = [
            (day(2026, 12, 14), .rotation1, false),
            (day(2026, 12, 15), .rotation2, false),
            (day(2026, 12, 16), .rotation1, true),
            (day(2026, 12, 17), .rotation2, true),
        ]
        for (target, rotation, uncertain) in expectations {
            let timeline = resolveDay(target, inputs: TestSupport.inputs(map: map))
            #expect(timeline.rotation == rotation, "\(target)")
            #expect(timeline.rotationUncertain == uncertain, "\(target)")
        }
    }

    @Test func overrideWithRotationIsCertain() {
        let target = day(2026, 12, 17)
        let overrides = [target: DayOverride(
            day: target, type: .bell(family: .earlyDismissal, rotation: .rotation2))]
        let timeline = resolveDay(target, inputs: TestSupport.inputs(overrides: overrides))
        #expect(timeline.rotation == .rotation2)
        #expect(!timeline.rotationUncertain)
        #expect(timeline.provenance == .override)
    }

    @Test func overrideWithoutRotationStaysUncertain() {
        let target = day(2026, 12, 17)
        let overrides = [target: DayOverride(
            day: target, type: .bell(family: .earlyDismissal, rotation: nil))]
        let timeline = resolveDay(target, inputs: TestSupport.inputs(overrides: overrides))
        #expect(timeline.rotation == .rotation1)
        #expect(timeline.rotationUncertain)
    }
}
