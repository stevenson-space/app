import Foundation

extension DayTimeline {
    /// Expands personalized rows using the official A/B bells for display only.
    /// Countdown and notification moments retain the student's continuous classes.
    public func halfPeriodBlocks(catalog: BellScheduleCatalog,
                                 calendar: Calendar = SchoolTime.calendar) -> [ResolvedBlock] {
        guard let family,
              let schedule = catalog.schedule(family: family, rotation: rotation),
              schedule.hasABVariants else { return blocks }

        return blocks.flatMap { block -> [ResolvedBlock] in
            guard block.periodID.periodNumber != nil else { return [block] }
            let halves = schedule.abBlocks.compactMap { bell -> ResolvedBlock? in
                guard let half = bell.half,
                      let start = day.date(at: bell.start, calendar: calendar),
                      let end = day.date(at: bell.end, calendar: calendar),
                      start >= block.start, end <= block.end else { return nil }
                let label = bell.id.storageKey + half.rawValue
                return ResolvedBlock(
                    id: label, periodID: bell.id, customizationID: block.customizationID,
                    half: half, role: block.role, displayName: block.displayName,
                    room: block.room, spanLabel: label, start: start, end: end)
            }
            return halves.isEmpty ? [block] : halves.sorted { $0.start < $1.start }
        }
    }
}
