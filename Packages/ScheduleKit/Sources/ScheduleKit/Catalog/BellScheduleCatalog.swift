import Foundation

public enum CatalogError: Error, CustomStringConvertible, Equatable {
    case badTime(scheduleID: String, value: String)
    case emptySchedule(scheduleID: String)
    case invalidOrdering(scheduleID: String, detail: String)
    case invalidHalves(scheduleID: String, detail: String)
    case invalidRotation(scheduleID: String, value: Int)
    case duplicateID(String)

    public var description: String {
        switch self {
        case .badTime(let id, let value): return "\(id): unparseable time '\(value)'"
        case .emptySchedule(let id): return "\(id): no blocks"
        case .invalidOrdering(let id, let detail): return "\(id): \(detail)"
        case .invalidHalves(let id, let detail): return "\(id): \(detail)"
        case .invalidRotation(let id, let value): return "\(id): unsupported rotation \(value)"
        case .duplicateID(let id): return "duplicate schedule id '\(id)'"
        }
    }
}

/// The immutable set of bundled bell tables, validated on load. A malformed
/// bundle is a programmer error caught by tests — never a runtime fallback.
public struct BellScheduleCatalog: Sendable {
    public let all: [BellSchedule]
    private let byID: [String: BellSchedule]

    public static func loadBundled() throws -> BellScheduleCatalog {
        try BellScheduleCatalog(data: BundledResources.bellSchedulesData())
    }

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(FileDTO.self, from: data)
        var schedules: [BellSchedule] = []
        for dto in file.schedules {
            let full = try dto.fullBlocks.map { try $0.block(scheduleID: dto.id) }
            let ab = try (dto.abBlocks ?? []).map { try $0.block(scheduleID: dto.id) }
            // A present rotation must be one we support — an unknown value (e.g.
            // rotation 3) is bad bundled data, not a silent nil.
            var rotation: EDRotation?
            if let raw = dto.rotation {
                guard let parsed = EDRotation(rawValue: raw) else {
                    throw CatalogError.invalidRotation(scheduleID: dto.id, value: raw)
                }
                rotation = parsed
            }
            schedules.append(BellSchedule(
                id: dto.id,
                family: dto.family,
                rotation: rotation,
                displayName: dto.displayName,
                fullBlocks: full,
                abBlocks: ab))
        }
        try Self.validate(schedules)
        self.all = schedules
        self.byID = Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0) })
    }

    public func schedule(id: String) -> BellSchedule? { byID[id] }

    /// Looks up the concrete table for a family; Early Dismissal requires a
    /// rotation (defaults to rotation 1, the "uncertain" fallback).
    public func schedule(family: BellFamily, rotation: EDRotation? = nil) -> BellSchedule? {
        if family == .earlyDismissal {
            let rotation = rotation ?? .rotation1
            return all.first { $0.family == .earlyDismissal && $0.rotation == rotation }
        }
        return all.first { $0.family == family }
    }

    // MARK: - Validation

    private static func validate(_ schedules: [BellSchedule]) throws {
        var seen = Set<String>()
        for schedule in schedules {
            guard seen.insert(schedule.id).inserted else { throw CatalogError.duplicateID(schedule.id) }
            guard !schedule.fullBlocks.isEmpty else { throw CatalogError.emptySchedule(scheduleID: schedule.id) }

            for block in schedule.fullBlocks + schedule.abBlocks where block.start >= block.end {
                throw CatalogError.invalidOrdering(
                    scheduleID: schedule.id,
                    detail: "block \(block.id.storageKey) start !< end")
            }
            for (previous, next) in zip(schedule.fullBlocks, schedule.fullBlocks.dropFirst())
            where next.start < previous.end {
                // Zero-length gaps (Makeup) are data; overlaps are errors.
                throw CatalogError.invalidOrdering(
                    scheduleID: schedule.id,
                    detail: "\(next.id.storageKey) starts before \(previous.id.storageKey) ends")
            }

            // A/B rows must pair up and sit inside their parent period.
            let byPeriod = Dictionary(grouping: schedule.abBlocks, by: \.id)
            for (periodID, halves) in byPeriod {
                guard let parent = schedule.fullBlocks.first(where: { $0.id == periodID }) else {
                    throw CatalogError.invalidHalves(
                        scheduleID: schedule.id,
                        detail: "halves for \(periodID.storageKey) with no parent block")
                }
                guard halves.count == 2,
                      let a = halves.first(where: { $0.half == .a }),
                      let b = halves.first(where: { $0.half == .b }) else {
                    throw CatalogError.invalidHalves(
                        scheduleID: schedule.id,
                        detail: "\(periodID.storageKey) must have exactly an A and a B half")
                }
                guard a.start == parent.start, b.end == parent.end, a.end < b.start else {
                    throw CatalogError.invalidHalves(
                        scheduleID: schedule.id,
                        detail: "\(periodID.storageKey) halves don't tile the parent period")
                }
            }
        }
    }

    // MARK: - DTOs

    private struct FileDTO: Decodable {
        let schedules: [ScheduleDTO]
    }

    private struct ScheduleDTO: Decodable {
        let id: String
        let family: BellFamily
        let rotation: Int?
        let displayName: String
        let fullBlocks: [BlockDTO]
        let abBlocks: [BlockDTO]?
    }

    private struct BlockDTO: Decodable {
        let period: String
        let half: String?
        let start: String
        let end: String

        func block(scheduleID: String) throws -> Block {
            guard let id = PeriodID(storageKey: period) else {
                throw CatalogError.invalidOrdering(scheduleID: scheduleID, detail: "unknown period '\(period)'")
            }
            guard let start = HourMinute(string: start) else {
                throw CatalogError.badTime(scheduleID: scheduleID, value: self.start)
            }
            guard let end = HourMinute(string: end) else {
                throw CatalogError.badTime(scheduleID: scheduleID, value: self.end)
            }
            let half = half.flatMap(Half.init(rawValue:))
            return Block(id: id, half: half, start: start, end: end)
        }
    }
}
