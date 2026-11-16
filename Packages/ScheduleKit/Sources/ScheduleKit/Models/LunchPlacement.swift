import Foundation

/// A student's answer to "when is your lunch?": which period, how much of it,
/// and what the rest of that period holds.
///
/// Everything a placement decides lives in the lunch period's own plan: the
/// lunch slots, a paired advisory, a free half, and a neighbouring class's
/// claim on a half are all stored there. So applying one is repeatable: return
/// the old lunch period to a plain class, then write the new one.
public struct LunchPlacement: Equatable, Hashable, Sendable {
    /// What fills the half of the lunch period that lunch leaves over.
    public enum OtherHalf: Hashable, CaseIterable, Sendable {
        case free
        /// Freshman advisory, which only ever sits beside lunch.
        case advisory
        /// The class next door runs 1½ periods and takes it.
        case neighborClass
    }

    public var period: Int
    public var portion: HalfChoice
    /// Ignored when lunch takes the whole period.
    public var otherHalf: OtherHalf

    public init(period: Int, portion: HalfChoice = .full, otherHalf: OtherHalf = .free) {
        self.period = period
        self.portion = portion
        self.otherHalf = otherHalf
    }

    /// The half lunch leaves over, or nil when it takes the whole period.
    public var remainingHalf: Half? {
        switch portion {
        case .a: return .b
        case .b: return .a
        case .full: return nil
        }
    }

    /// The period whose class would run long into the remaining half: the one
    /// before a B lunch, the one after an A lunch.
    public var neighborPeriod: Int? {
        switch portion {
        case .a: return period + 1
        case .b: return period - 1
        case .full: return nil
        }
    }
}

extension UserConfig {
    /// The placement the grid describes, or nil without a lunch. A leftover
    /// half that still holds the period's own class reads as free, since a
    /// half period is only ever lunch, advisory, free, or part of a longer class.
    public var lunchPlacement: LunchPlacement? {
        guard let lunch else { return nil }
        var placement = LunchPlacement(period: lunch.basePeriod, portion: lunch.choice)
        guard let remaining = placement.remainingHalf,
              let neighbor = placement.neighborPeriod else { return placement }
        switch plan(for: lunch.basePeriod).slot(remaining) {
        case .advisory:
            placement.otherHalf = .advisory
        case .classSlot(let anchor) where anchor == neighbor:
            placement.otherHalf = .neighborClass
        default:
            placement.otherHalf = .free
        }
        return placement
    }

    /// Whether the class beside the half `placement` leaves over is there to
    /// run long into it. Judged without the current lunch, which applying the
    /// placement would move out of the way first.
    public func neighborClassCanFill(_ placement: LunchPlacement) -> Bool {
        var cleared = self
        cleared.clearLunchPeriod()
        return cleared.neighborClassReachesEdge(of: placement)
    }

    /// Moves lunch to `placement`, or removes it for nil. Lunch only sits in
    /// periods 4–6; a placement anywhere else just clears the current one. A
    /// neighbouring class that isn't there to run long leaves its half free.
    public mutating func setLunchPlacement(_ placement: LunchPlacement?) {
        clearLunchPeriod()
        guard let placement, Self.advisoryPeriods.contains(placement.period) else { return }
        let period = placement.period
        guard let remaining = placement.remainingHalf,
              let neighbor = placement.neighborPeriod else {
            lunch = SplitAssignment(basePeriod: period, choice: .full)
            return
        }

        let runsLong = placement.otherHalf == .neighborClass
            && neighborClassReachesEdge(of: placement)
        if placement.otherHalf == .advisory {
            setPairedAdvisory(basePeriod: period, advisoryHalf: remaining)
        } else {
            lunch = SplitAssignment(basePeriod: period, choice: placement.portion)
            if runsLong {
                setClassLength(anchor: neighbor, remaining == .a ? .extendsForward : .startsEarly)
            } else {
                setSlot(period: period, half: remaining, to: .free)
            }
        }
        // The period no longer holds a class of its own, so any 1½-period
        // claim that class had next door would dangle.
        retractClassClaims(anchor: period)
    }

    /// Returns the current lunch period to a plain class, taking a paired
    /// advisory, a free half, or a neighbour's claim on it along.
    private mutating func clearLunchPeriod() {
        guard let lunch else { return }
        setPlan(.standardClass(lunch.basePeriod), for: lunch.basePeriod)
    }

    /// The neighbour's own class has to reach the edge it shares with the
    /// lunch period, or there is nothing to extend.
    private func neighborClassReachesEdge(of placement: LunchPlacement) -> Bool {
        guard let remaining = placement.remainingHalf,
              let neighbor = placement.neighborPeriod,
              Self.periodRange.contains(neighbor) else { return false }
        let facing: Half = remaining == .a ? .b : .a
        return plan(for: neighbor).slot(facing) == .classSlot(anchor: neighbor)
    }
}
