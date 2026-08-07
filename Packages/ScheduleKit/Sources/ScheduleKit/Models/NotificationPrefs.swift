import Foundation

/// Notification preferences. Everything defaults to OFF — an app that spams a
/// student during class gets deleted.
public struct NotificationPrefs: Equatable, Sendable {
    public var blockEndEnabled: Bool
    /// Minutes before a block ends to fire the heads-up.
    public var blockEndLeadMinutes: Int
    public var morningEnabled: Bool
    /// Wall-clock time for the non-standard-day morning alert.
    public var morningTime: HourMinute

    public init(blockEndEnabled: Bool = false,
                blockEndLeadMinutes: Int = 5,
                morningEnabled: Bool = false,
                morningTime: HourMinute = HourMinute(hour: 7, minute: 0)) {
        self.blockEndEnabled = blockEndEnabled
        self.blockEndLeadMinutes = blockEndLeadMinutes
        self.morningEnabled = morningEnabled
        self.morningTime = morningTime
    }

    public var anyEnabled: Bool { blockEndEnabled || morningEnabled }
}

extension NotificationPrefs: Codable {
    private enum CodingKeys: String, CodingKey {
        case blockEndEnabled, blockEndLeadMinutes, morningEnabled, morningTime
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockEndEnabled = try c.decodeIfPresent(Bool.self, forKey: .blockEndEnabled) ?? false
        blockEndLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .blockEndLeadMinutes) ?? 5
        morningEnabled = try c.decodeIfPresent(Bool.self, forKey: .morningEnabled) ?? false
        morningTime = try c.decodeIfPresent(HourMinute.self, forKey: .morningTime)
            ?? HourMinute(hour: 7, minute: 0)
    }
}
