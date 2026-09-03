import Foundation

/// Everything the resolver reads, in one App-Group-ready store. The main app
/// writes; future widget/Live Activity targets read the same suite — which is
/// the whole point: every surface computes from identical inputs.
///
/// Until the App Group entitlement lands (widgets phase), the suite behaves
/// like private storage; `migrateFromStandardIfNeeded` is the one-time path
/// for any data written before a suite existed.
public final class SharedStore: @unchecked Sendable {
    public static let appGroupID = "group.shankar.Stevenson-Space-Companion-App"
    public static let defaultMapURL = URL(
        string: "https://raw.githubusercontent.com/stevenson-space/shs/main/src/data/schedule-dates.json")!
    public static let defaultLunchMenuURL = URL(
        string: "https://raw.githubusercontent.com/stevenson-space/shs/main/src/data/lunch-menu.json")!

    private let defaults: UserDefaults

    private enum Keys {
        static let userConfig = "sk.userConfig"
        static let overrides = "sk.overrides"
        static let mapData = "sk.mapData"
        static let fetchMetadata = "sk.fetchMetadata"
        static let notificationPrefs = "sk.notificationPrefs"
        static let mapURL = "sk.mapURL"
        static let lunchMenuData = "sk.lunchMenuData"
        static let lunchFetchMetadata = "sk.lunchFetchMetadata"
        static let studentID = "sk.studentID"
        static let studentIDPhotoHidden = "sk.studentIDPhotoHidden"
        static let migrated = "sk.migratedToAppGroup"
        static let mapURLRetired = "sk.mapURLRetired"
        static let all = [userConfig, overrides, mapData, fetchMetadata,
                          notificationPrefs, mapURL, lunchMenuData,
                          lunchFetchMetadata, studentID, studentIDPhotoHidden]
    }

    /// Every key the one-time App Group migration carries across.
    static var migratableKeys: [String] { Keys.all }

    /// Test injection point.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public convenience init() {
        if let suite = UserDefaults(suiteName: SharedStore.appGroupID) {
            self.init(defaults: suite)
            migrateFromStandardIfNeeded()
        } else {
            self.init(defaults: .standard)
        }
        retireCustomMapURLIfNeeded()
    }

    /// The in-app data-source editor (the only way to set or reset a custom
    /// `mapURL`) was removed. Any URL it had persisted would otherwise stay
    /// active forever with no recovery path. Drop it once so upgraded installs
    /// return to the supported default source.
    func retireCustomMapURLIfNeeded() {
        guard !defaults.bool(forKey: Keys.mapURLRetired) else { return }
        resetMapURL()
        defaults.set(true, forKey: Keys.mapURLRetired)
    }

    /// Copies any pre-App-Group data from `.standard` into the suite, once.
    func migrateFromStandardIfNeeded() {
        guard !defaults.bool(forKey: Keys.migrated) else { return }
        let standard = UserDefaults.standard
        for key in Keys.all where defaults.object(forKey: key) == nil {
            if let value = standard.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: Keys.migrated)
    }

    // MARK: - Typed accessors

    public var userConfig: UserConfig {
        get { decode(UserConfig.self, key: Keys.userConfig) ?? UserConfig() }
        set { encode(newValue, key: Keys.userConfig) }
    }

    public var overrides: [DayOverride] {
        get { decode([DayOverride].self, key: Keys.overrides) ?? [] }
        set { encode(newValue, key: Keys.overrides) }
    }

    public var overridesByDay: [DayKey: DayOverride] {
        Dictionary(overrides.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Raw bytes of the last successfully validated remote map (last-good cache).
    public var cachedMapData: Data? {
        get { defaults.data(forKey: Keys.mapData) }
        set { defaults.set(newValue, forKey: Keys.mapData) }
    }

    public var fetchMetadata: FetchMetadata {
        get { decode(FetchMetadata.self, key: Keys.fetchMetadata) ?? FetchMetadata() }
        set { encode(newValue, key: Keys.fetchMetadata) }
    }

    /// Raw bytes of the last successfully validated lunch manifest.
    public var cachedLunchMenuData: Data? {
        get { defaults.data(forKey: Keys.lunchMenuData) }
        set { defaults.set(newValue, forKey: Keys.lunchMenuData) }
    }

    public var lunchFetchMetadata: FetchMetadata {
        get { decode(FetchMetadata.self, key: Keys.lunchFetchMetadata) ?? FetchMetadata() }
        set { encode(newValue, key: Keys.lunchFetchMetadata) }
    }

    /// The student's ID card, as opaque bytes.
    ///
    /// Deliberately untyped here: the card model lives in StudentIDKit, and
    /// ScheduleKit has no business depending on it. Keeping the key in this
    /// store anyway means the ID rides along with everything else the day the
    /// App Group entitlement lands and widgets need to read it.
    public var studentIDData: Data? {
        get { defaults.data(forKey: Keys.studentID) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.studentID)
            } else {
                defaults.removeObject(forKey: Keys.studentID)
            }
        }
    }

    /// A display preference; hiding the photo keeps the saved image available.
    public var studentIDPhotoHidden: Bool {
        get { defaults.bool(forKey: Keys.studentIDPhotoHidden) }
        set { defaults.set(newValue, forKey: Keys.studentIDPhotoHidden) }
    }

    public var notificationPrefs: NotificationPrefs {
        get { decode(NotificationPrefs.self, key: Keys.notificationPrefs) ?? NotificationPrefs() }
        set { encode(newValue, key: Keys.notificationPrefs) }
    }

    /// The remote map URL — user-editable in Settings, resettable to default.
    public var mapURL: URL {
        get {
            guard let raw = defaults.string(forKey: Keys.mapURL), let url = URL(string: raw) else {
                return SharedStore.defaultMapURL
            }
            return url
        }
        set { defaults.set(newValue.absoluteString, forKey: Keys.mapURL) }
    }

    public var isUsingDefaultMapURL: Bool { mapURL == SharedStore.defaultMapURL }

    public func resetMapURL() {
        defaults.removeObject(forKey: Keys.mapURL)
    }

    // MARK: - Codable plumbing

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}

/// Sync bookkeeping, shown in Settings ("last updated" / "last changed") and
/// used for throttling and staleness hints.
public struct FetchMetadata: Equatable, Sendable {
    public var lastAttempt: Date?
    /// Last time the server was reached and the payload validated (200 or 304).
    public var lastSuccess: Date?
    /// Last time the content actually changed.
    public var lastChanged: Date?
    public var etag: String?
    public var lastError: String?

    public init(lastAttempt: Date? = nil, lastSuccess: Date? = nil,
                lastChanged: Date? = nil, etag: String? = nil, lastError: String? = nil) {
        self.lastAttempt = lastAttempt
        self.lastSuccess = lastSuccess
        self.lastChanged = lastChanged
        self.etag = etag
        self.lastError = lastError
    }
}

extension FetchMetadata: Codable {
    private enum CodingKeys: String, CodingKey {
        case lastAttempt, lastSuccess, lastChanged, etag, lastError
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastAttempt = try c.decodeIfPresent(Date.self, forKey: .lastAttempt)
        lastSuccess = try c.decodeIfPresent(Date.self, forKey: .lastSuccess)
        lastChanged = try c.decodeIfPresent(Date.self, forKey: .lastChanged)
        etag = try c.decodeIfPresent(String.self, forKey: .etag)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
    }
}
