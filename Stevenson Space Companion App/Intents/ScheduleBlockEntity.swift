import AppIntents
import Foundation
import ScheduleKit

/// Results describe a particular invocation, not a permanently saved class.
/// Transient entities keep Shortcuts fields usable without stale entity lookups.
struct ScheduleBlockEntity: TransientAppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Schedule Block"

    @Property(title: "Name") var name: String
    @Property(title: "Period") var period: String
    @Property(title: "Room") var room: String?
    @Property(title: "Start Time") var startTime: Date
    @Property(title: "End Time") var endTime: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(period)")
    }

    init() {}

    init(_ block: ResolvedBlock) {
        name = block.displayName
        period = block.spanLabel ?? block.periodID.defaultDisplayName
        room = block.room
        startTime = block.start
        endTime = block.end
    }
}
