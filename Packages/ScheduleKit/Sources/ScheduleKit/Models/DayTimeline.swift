import Foundation

public enum BlockRole: String, Codable, Hashable, Sendable {
    case classPeriod
    case lunch
    case advisory
    case free
    case homeroom
    case activity
    case assembly
    case makeup
    case summerSchool

    /// Roles the student actually attends (drives notifications and countdown focus).
    public var isAttended: Bool { self != .free }
}

/// One concrete personalized block on a specific day, with materialized instants.
/// Intervals are half-open: [start, end).
public struct ResolvedBlock: Identifiable, Hashable, Sendable {
    /// Stable within the day, e.g. "4", "4A", "2+3A", "makeup". Notification
    /// identifiers reuse it.
    public let id: String
    /// Identity for customization/rotation purposes; a merged 1½-period class
    /// carries its anchor period.
    public let periodID: PeriodID
    public let half: Half?
    public let role: BlockRole
    public let displayName: String
    public let room: String?
    /// UI capsule text: nil for a plain full period, "4A" for a half, and a
    /// range like "2–3A" for a merged 1½-period class.
    public let spanLabel: String?
    public let start: Date
    public let end: Date

    public init(id: String, periodID: PeriodID, half: Half?, role: BlockRole,
                displayName: String, room: String?, spanLabel: String? = nil,
                start: Date, end: Date) {
        self.id = id
        self.periodID = periodID
        self.half = half
        self.role = role
        self.displayName = displayName
        self.room = room
        self.spanLabel = spanLabel
        self.start = start
        self.end = end
    }
}

/// What the state machine walks: blocks, with runs of consecutive free blocks
/// (and the gaps between them) merged into single spans so the countdown never
/// counts down a class the user doesn't attend.
public struct ResolvedSpan: Identifiable, Hashable, Sendable {
    public let id: String
    public let role: BlockRole
    public let displayName: String
    public let room: String?
    public let start: Date
    public let end: Date
    /// Identity of the underlying period when the span is a single block —
    /// `nil` for merged free spans. Drives intra-period passing detection.
    public let periodID: PeriodID?
    public let half: Half?
    public let blockIDs: [String]

    public init(id: String, role: BlockRole, displayName: String, room: String?,
                start: Date, end: Date, periodID: PeriodID?, half: Half?, blockIDs: [String]) {
        self.id = id
        self.role = role
        self.displayName = displayName
        self.room = room
        self.start = start
        self.end = end
        self.periodID = periodID
        self.half = half
        self.blockIDs = blockIDs
    }
}

public enum DayKind: Hashable, Sendable {
    case school
    case weekend
    case breakDay(label: String)
    case noSchool
    case asynchronous
    case outsideYear
    case unknownType(name: String)
}

/// Why the app believes today is what it is — drives the header trust indicator.
public enum Provenance: Hashable, Sendable {
    /// Listed in the remote map.
    case remoteMap
    /// Unlisted in-session weekday: Standard by design, not a guess.
    case defaultStandard
    /// User-forced type for this date.
    case override
    /// Bundled break range (winter/spring break).
    case bundledBreak
    case weekend
    case outsideYear
}

public struct DayTimeline: Hashable, Sendable {
    public let day: DayKey
    public let kind: DayKind
    public let family: BellFamily?
    public let rotation: EDRotation?
    public let scheduleLabel: String
    /// Extra context line: "Freshman Orientation", "Finals Day 1", …
    public let dayNote: String?
    public let provenance: Provenance
    public let rotationUncertain: Bool
    /// Display list (every personalized block, including both halves of a split).
    public let blocks: [ResolvedBlock]
    /// State-machine list (free runs merged).
    public let moments: [ResolvedSpan]

    public init(day: DayKey, kind: DayKind, family: BellFamily?, rotation: EDRotation?,
                scheduleLabel: String, dayNote: String?, provenance: Provenance,
                rotationUncertain: Bool, blocks: [ResolvedBlock], moments: [ResolvedSpan]) {
        self.day = day
        self.kind = kind
        self.family = family
        self.rotation = rotation
        self.scheduleLabel = scheduleLabel
        self.dayNote = dayNote
        self.provenance = provenance
        self.rotationUncertain = rotationUncertain
        self.blocks = blocks
        self.moments = moments
    }

    public var firstBell: Date? { moments.first?.start }
    public var lastBell: Date? { moments.last?.end }
    public var isSchoolDay: Bool { kind == .school }
    public var isStandardSchedule: Bool { family == .standard }
}

public enum PassingKind: Hashable, Sendable {
    /// Ordinary hallway passing between two periods.
    case betweenPeriods
    /// The gap inside a period between its A and B halves.
    case intraPeriod
}

public enum MomentState: Hashable, Sendable {
    case beforeSchool(first: ResolvedSpan)
    case inBlock(current: ResolvedSpan, next: ResolvedSpan?)
    case passing(from: ResolvedSpan, to: ResolvedSpan, kind: PassingKind)
    case afterSchool
    case weekend
    case breakDay(label: String)
    case noSchool
    case asynchronous
    case outsideYear
    case unknownSchedule(name: String)
}
