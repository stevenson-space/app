import Testing
import Foundation
@testable import ScheduleKit

@Suite struct MomentStateTests {
    let monday = day(2026, 9, 14) // Standard day

    func standard(_ config: UserConfig = UserConfig()) -> DayTimeline {
        resolveDay(monday, inputs: TestSupport.inputs(config: config))
    }

    func state(_ timeline: DayTimeline, _ hour: Int, _ minute: Int, _ second: Int = 0) -> MomentState {
        momentState(at: TestSupport.at(timeline.day, hour, minute, second), in: timeline)
    }

    @Test func beforeSchool() {
        let t = standard()
        guard case .beforeSchool(let first) = state(t, 7, 45) else {
            Issue.record("expected beforeSchool"); return
        }
        #expect(first.id == "1")
        // One second before the bell is still before school.
        guard case .beforeSchool = state(t, 8, 29, 59) else {
            Issue.record("expected beforeSchool at 8:29:59"); return
        }
    }

    @Test func halfOpenIntervalBoundaries() {
        let t = standard()
        // The exact start second is inside the block.
        guard case .inBlock(let current, let next) = state(t, 8, 30) else {
            Issue.record("expected inBlock at 8:30:00"); return
        }
        #expect(current.id == "1")
        #expect(next?.id == "2")

        // The exact end second has already left the block: passing begins.
        guard case .passing(let from, let to, let kind) = state(t, 9, 21) else {
            Issue.record("expected passing at 9:21:00"); return
        }
        #expect(from.id == "1")
        #expect(to.id == "2")
        #expect(kind == .betweenPeriods)

        // The next block's start second enters it.
        guard case .inBlock(let second, _) = state(t, 9, 26) else {
            Issue.record("expected inBlock at 9:26:00"); return
        }
        #expect(second.id == "2")
    }

    @Test func intraPeriodPassingBetweenLunchHalves() {
        let t = standard(UserConfig(lunch: SplitAssignment(basePeriod: 4, choice: .a)))

        guard case .inBlock(let lunch, _) = state(t, 11, 15) else {
            Issue.record("expected lunch block"); return
        }
        #expect(lunch.role == .lunch)

        guard case .passing(let from, let to, let kind) = state(t, 11, 33) else {
            Issue.record("expected intra-period passing at 11:33"); return
        }
        #expect(kind == .intraPeriod)
        #expect(from.id == "4A")
        #expect(to.id == "4B")

        guard case .inBlock(let classHalf, _) = state(t, 11, 37) else {
            Issue.record("expected 4B at 11:37"); return
        }
        #expect(classHalf.id == "4B")
        #expect(classHalf.role == .classPeriod)
    }

    @Test func zeroGapMakeupNeverShowsPassing() throws {
        let map = try TestSupport.map(#"{"Early Dismissal": ["12/17/2026-12/18/2026"]}"#)
        let t = resolveDay(day(2026, 12, 17), inputs: TestSupport.inputs(map: map))

        guard case .inBlock(let fourth, _) = state(t, 11, 39, 59) else {
            Issue.record("expected period 4 at 11:39:59"); return
        }
        #expect(fourth.id == "4")

        // At 11:40:00 exactly, Makeup has begun — no passing state exists.
        guard case .inBlock(let makeup, let next) = state(t, 11, 40) else {
            Issue.record("expected Makeup at 11:40:00"); return
        }
        #expect(makeup.id == "makeup")
        #expect(next == nil)

        // Normal finals passing gaps still read as passing.
        guard case .passing(_, _, .betweenPeriods) = state(t, 10, 0) else {
            Issue.record("expected passing at 10:00"); return
        }
    }

    @Test func mergedFreeSpanCountsAsOneBlock() {
        let t = standard(UserConfig(freePeriods: [6, 7]))

        // Mid period 6 and mid the 6→7 gap both sit inside the merged span.
        for (h, m) in [(13, 0), (13, 43), (14, 0)] {
            guard case .inBlock(let span, let next) = state(t, h, m) else {
                Issue.record("expected free span at \(h):\(m)"); return
            }
            #expect(span.role == .free)
            #expect(span.end == TestSupport.at(monday, 14, 33))
            #expect(next?.id == "8")
        }

        // The trailing gap before period 8 is ordinary passing.
        guard case .passing(let from, let to, .betweenPeriods) = state(t, 14, 35) else {
            Issue.record("expected passing at 14:35"); return
        }
        #expect(from.role == .free)
        #expect(to.id == "8")
    }

    @Test func afterSchool() {
        let t = standard()
        guard case .inBlock(let last, let next) = state(t, 15, 24, 59) else {
            Issue.record("expected period 8 at 15:24:59"); return
        }
        #expect(last.id == "8")
        #expect(next == nil)

        guard case .afterSchool = state(t, 15, 25) else {
            Issue.record("expected afterSchool at 15:25:00"); return
        }
        guard case .afterSchool = state(t, 22, 0) else {
            Issue.record("expected afterSchool at night"); return
        }
    }

    @Test func nonSchoolKindsPassThrough() throws {
        #expect(momentState(at: Date(), in: resolveDay(day(2026, 9, 19), inputs: TestSupport.inputs())) == .weekend)
        #expect(momentState(at: Date(), in: resolveDay(day(2026, 12, 23), inputs: TestSupport.inputs()))
                == .breakDay(label: "Winter Break"))
        #expect(momentState(at: Date(), in: resolveDay(day(2026, 7, 31), inputs: TestSupport.inputs())) == .outsideYear)

        let asyncMap = try TestSupport.map(#"{"Asynchronous": ["11/13/2026"]}"#)
        #expect(momentState(at: Date(), in: resolveDay(day(2026, 11, 13), inputs: TestSupport.inputs(map: asyncMap)))
                == .asynchronous)

        let noSchoolMap = try TestSupport.map(#"{"No School": ["11/25/2026"]}"#)
        #expect(momentState(at: Date(), in: resolveDay(day(2026, 11, 25), inputs: TestSupport.inputs(map: noSchoolMap)))
                == .noSchool)

        let unknownMap = try TestSupport.map(#"{"Mystery": ["10/6/2026"]}"#)
        #expect(momentState(at: Date(), in: resolveDay(day(2026, 10, 6), inputs: TestSupport.inputs(map: unknownMap)))
                == .unknownSchedule(name: "Mystery"))
    }

    @Test func dstMondaysKeepWallClockTimes() {
        // Monday after fall-back (Nov 2 2026) and after spring-forward (Mar 15 2027).
        for target in [day(2026, 11, 2), day(2027, 3, 15)] {
            let t = resolveDay(target, inputs: TestSupport.inputs())
            #expect(t.kind == .school, "\(target)")
            let first = t.blocks.first!
            #expect(first.start == TestSupport.at(target, 8, 30), "\(target)")
            #expect(first.end.timeIntervalSince(first.start) == 51 * 60, "\(target)")

            guard case .inBlock(let block, _) = momentState(at: TestSupport.at(target, 8, 30), in: t) else {
                Issue.record("expected inBlock on \(target)"); return
            }
            #expect(block.id == "1")
        }
    }

    @Test func lateArrivalMorningIsBeforeSchoolNotPassing() throws {
        let map = try TestSupport.map(#"{"Late Arrival": ["9/18/2026"]}"#)
        let t = resolveDay(day(2026, 9, 18), inputs: TestSupport.inputs(map: map))
        guard case .beforeSchool(let first) = momentState(at: TestSupport.at(day(2026, 9, 18), 9, 0), in: t) else {
            Issue.record("expected beforeSchool at 9:00 on Late Arrival"); return
        }
        #expect(first.start == TestSupport.at(day(2026, 9, 18), 10, 30))
    }
}
