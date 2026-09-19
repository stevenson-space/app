import Foundation

/// Everything the resolver reads, in one App-Group-ready store. The main app
/// writes; widget targets read the same suite — which is
/// the whole point: every surface computes from identical inputs.
///
/// Only the main app constructs this store. Extensions use `readScheduleData()`
/// instead, which reads schedule keys without initializing secrets or migrating.
public final class SharedStore: @unchecked Sendable {
    public static let appGroupID = "group.shankar.Stevenson-Space-Companion-App"
    public static let defaultMapURL = URL(
        string: "https://raw.githubusercontent.com/stevenson-space/shs/main/src/data/schedule-dates.json")!
    /// The website publishes the lunch rotation as one file per station under
    /// `src/data/lunch-rotating`. There is no consolidated manifest, so the app
    /// fetches every station and assembles the manifest itself.
    public static let lunchStationNames = [
        "comfort", "international", "mindful", "sides", "soup", "special",
    ]

    public static func lunchStationURL(named name: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/stevenson-space/shs/main/src/data/lunch-rotating/\(name).json")!
    }

    /// Hosts the schedule manifest and the lunch station files. Every remote
    /// source the app is allowed to reach lives here; nothing else is fetchable.
    public static let allowedHosts: Set<String> = ["raw.githubusercontent.com"]

    private let defaults: UserDefaults
    private let secrets: SecretStore
    /// Where this app kept its preferences before the App Group suite existed.
    /// A separate property only so tests can point it somewhere harmless.
    private let legacyDefaults: UserDefaults
    private var legacyPrivateSuiteURL: URL?

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
        static let widgetDataReady = "sk.widgetDataReady"
        static let privateSuiteMigrated = "sk.privateSuiteMigrated"
        static let migrated = "sk.migratedToAppGroup"
        static let mapURLRetired = "sk.mapURLRetired"
        static let all = [userConfig, overrides, mapData, fetchMetadata,
                          notificationPrefs, mapURL, lunchMenuData,
                          lunchFetchMetadata, studentID, studentIDPhotoHidden]
    }

    /// Every key the one-time App Group migration carries across.
    static var migratableKeys: [String] { Keys.all }

    /// Test injection point. Pass an `InMemorySecretStore` so tests never reach
    /// the host's real keychain, and a scratch suite as `legacyDefaults` so
    /// they never write to the host's standard defaults either.
    public init(defaults: UserDefaults, secrets: SecretStore,
                legacyDefaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.secrets = secrets
        self.legacyDefaults = legacyDefaults
    }

    public convenience init() {
        if let suite = UserDefaults(suiteName: SharedStore.appGroupID) {
            self.init(defaults: suite, secrets: KeychainSecretStore())
            // Before entitlements, suiteName could write a private preferences
            // domain inside the app container. Import it before standard defaults.
            migrateFromPrivateSuiteIfNeeded()
            migrateFromStandardIfNeeded()
        } else {
            self.init(defaults: .standard, secrets: KeychainSecretStore())
        }
        // Order matters: the App Group migration must land any legacy blob in
        // this suite before the keychain migration goes looking for it.
        migrateStudentIDToKeychainIfNeeded()
        retireCustomMapURLIfNeeded()
    }

    /// Main-app-only upgrade from the formerly unentitled suite. An independent
    /// marker is required: the old suite may already contain the standard-store
    /// migration marker. Never replace newer values in the shared container.
    func migrateFromPrivateSuiteIfNeeded(fileURL: URL? = nil) {
        guard !defaults.bool(forKey: Keys.privateSuiteMigrated) else { return }
        let url = fileURL ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences/\(Self.appGroupID).plist")
        guard let data = try? Data(contentsOf: url),
              var values = (try? PropertyListSerialization.propertyList(from: data, format: nil))
                as? [String: Any] else { return }
        legacyPrivateSuiteURL = url
        for key in Keys.all where key != Keys.studentID && defaults.object(forKey: key) == nil {
            if let value = values[key] { defaults.set(value, forKey: key) }
        }
        // Keep identity in the app's keychain; never copy it into the App Group.
        if let identity = values[Keys.studentID] as? Data {
            switch secrets.read(Keys.studentID) {
            case .unavailable: return
            case .missing:
                guard (try? secrets.write(identity, for: Keys.studentID)) != nil else { return }
            case .value: break
            }
            values.removeValue(forKey: Keys.studentID)
            guard let cleaned = try? PropertyListSerialization.data(
                fromPropertyList: values, format: .binary, options: 0),
                  (try? cleaned.write(to: url, options: .atomic)) != nil else { return }
        }
        defaults.set(true, forKey: Keys.privateSuiteMigrated)
    }

    /// Call in the main app after protected data becomes available. Retry imports
    /// before publishing readiness, so an empty locked launch cannot masquerade
    /// as a new user's default configuration.
    public func prepareScheduleDataForWidgets() {
        migrateFromPrivateSuiteIfNeeded()
        migrateFromStandardIfNeeded()
        retireCustomMapURLIfNeeded()
        defaults.set(true, forKey: Keys.widgetDataReady)
    }

    /// Schedule-only snapshot. This path never creates SharedStore, a SecretStore,
    /// or a reference to standard defaults and never writes or runs migrations.
    public static func readScheduleData() throws -> SharedScheduleData {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil,
              let suite = UserDefaults(suiteName: appGroupID) else {
            throw SharedScheduleDataError.unavailable
        }
        return try readScheduleData(from: suite)
    }

    static func readScheduleData(from defaults: UserDefaults) throws -> SharedScheduleData {
        guard defaults.bool(forKey: Keys.widgetDataReady) else {
            throw SharedScheduleDataError.unavailable
        }
        func read<T: Decodable>(_ type: T.Type, key: String, fallback: T) throws -> T {
            guard let value = defaults.object(forKey: key) else { return fallback }
            guard let data = value as? Data else { throw SharedScheduleDataError.unavailable }
            return try JSONDecoder().decode(type, from: data)
        }
        let config = try read(UserConfig.self, key: Keys.userConfig, fallback: UserConfig())
        let overrides = try read([DayOverride].self, key: Keys.overrides, fallback: [])
        let map: DayTypeMap?
        if let value = defaults.object(forKey: Keys.mapData) {
            guard let data = value as? Data else { throw SharedScheduleDataError.unavailable }
            map = try ScheduleDatesParser.parse(data)
        } else {
            // An absent remote cache uses the resolver's bundled school calendar
            // and documented Standard fallback, just like the main app.
            map = nil
        }
        return SharedScheduleData(config: config, overrides: overrides, map: map)
    }

    /// The in-app data-source editor (the only way to set or reset a custom
    /// `mapURL`) was removed. Any URL it had persisted would otherwise stay
    /// active forever with no recovery path. Drop it once so upgraded installs
    /// return to the supported default source.
    func retireCustomMapURLIfNeeded() {
        // Clean up both stores even if an earlier launch already recorded the
        // retirement. Otherwise a later migration pass could reintroduce the
        // legacy value from the standard defaults suite.
        if defaults.bool(forKey: Keys.mapURLRetired) {
            defaults.removeObject(forKey: Keys.mapURL)
            legacyDefaults.removeObject(forKey: Keys.mapURL)
            return
        }
        resetMapURL()
        legacyDefaults.removeObject(forKey: Keys.mapURL)
        defaults.set(true, forKey: Keys.mapURLRetired)
    }

    /// Copies any pre-App-Group data from `.standard` into the suite, once.
    /// The student ID is copied like everything else and deliberately not
    /// deleted here: `migrateStudentIDToKeychainIfNeeded` drops both plaintext
    /// copies together, once the keychain is known to hold the card.
    func migrateFromStandardIfNeeded() {
        guard !defaults.bool(forKey: Keys.migrated) else { return }
        var copied = false
        for key in Keys.all where defaults.object(forKey: key) == nil {
            // A retired custom URL must never be copied back from the old
            // suite. Other keys remain eligible for migration and retries.
            if key == Keys.mapURL && defaults.bool(forKey: Keys.mapURLRetired) {
                continue
            }
            if let value = legacyDefaults.object(forKey: key) {
                defaults.set(value, forKey: key)
                copied = true
            }
        }
        // A launch before first unlock reads the old plist as empty, which is
        // indistinguishable from having nothing to migrate. Burning the
        // one-shot flag there would strand the config, overrides and prefs in
        // the old suite forever, so only a launch that actually carried
        // something across closes the door. On a genuinely fresh install the
        // loop keeps running — ten `object(forKey:)` reads, and the old suite
        // is empty, so there is nothing left for it to resurrect.
        if copied {
            defaults.set(true, forKey: Keys.migrated)
        }
    }

    /// The plaintext card, wherever an older version left it: this suite, or
    /// the standard defaults from before the suite existed.
    private var legacyStudentIDData: Data? {
        defaults.data(forKey: Keys.studentID) ?? legacyDefaults.data(forKey: Keys.studentID)
            ?? privateSuiteValues?[Keys.studentID] as? Data
    }

    private var privateSuiteValues: [String: Any]? {
        try? readPrivateSuiteValues()
    }

    private func readPrivateSuiteValues() throws -> [String: Any]? {
        guard let url = legacyPrivateSuiteURL else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return values
    }

    /// Drops the plaintext card from every plist that could still hold one.
    /// Migration calls this after saving to the keychain; explicit removal must
    /// finish this cleanup before deleting the keychain value.
    private func clearPlaintextStudentID() throws {
        defaults.removeObject(forKey: Keys.studentID)
        legacyDefaults.removeObject(forKey: Keys.studentID)
        if let url = legacyPrivateSuiteURL, var values = try readPrivateSuiteValues(),
           values.removeValue(forKey: Keys.studentID) != nil {
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            try data.write(to: url, options: .atomic)
        }
    }

    /// Moves a student ID written by a version that kept it in `UserDefaults`
    /// into the keychain, once.
    ///
    /// The plist copy is deleted only after the keychain write succeeds — on a
    /// background launch with the device still locked the write fails, and the
    /// card must survive until an unlocked launch can move it.
    func migrateStudentIDToKeychainIfNeeded() {
        guard let legacy = legacyStudentIDData else { return }
        switch secrets.read(Keys.studentID) {
        case .value:
            // Already migrated; the plist copies are leftovers from a run whose
            // cleanup did not finish — including an install upgraded by a
            // version that cleared the suite but not the standard defaults.
            try? clearPlaintextStudentID()
        case .unavailable:
            // Locked. Reading nothing here does not mean there is nothing there,
            // so leave both copies alone and migrate on a later launch.
            return
        case .missing:
            guard (try? secrets.write(legacy, for: Keys.studentID)) != nil else { return }
            try? clearPlaintextStudentID()
        }
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

    /// The student's ID card, as opaque bytes, in the keychain.
    ///
    /// Deliberately untyped here: the card model lives in StudentIDKit, and
    /// ScheduleKit has no business depending on it. It is the one thing this
    /// store keeps outside `UserDefaults`, because a preferences plist is
    /// readable from a backup or an extracted container and carries the
    /// student's number and name in the clear.
    ///
    /// Device-only and unavailable while locked. Widgets use the schedule-only
    /// reader above and never access this value or share the app's keychain.
    public func readStudentIDData() -> SecretReadResult {
        let stored = secrets.read(Keys.studentID)
        guard case .missing = stored, let legacy = legacyStudentIDData else {
            return stored
        }
        // The keychain definitively has nothing while the plist still holds a
        // card, so the one-time move has not happened: the launch that would
        // have run it met a locked device, or its write failed. Retry it now
        // that something is actually asking for the card — `init()` runs the
        // migration once per launch, which is no help to a process that started
        // before first unlock.
        if (try? secrets.write(legacy, for: Keys.studentID)) != nil {
            try? clearPlaintextStudentID()
        }
        // Either way, serve the bytes the student still has. Reporting the card
        // as missing would blank the ID tab for the rest of the session and let
        // the launch-time orphan cleanup delete the photo that belongs to it.
        return .value(legacy)
    }

    /// Nil for both "no card saved" and "cannot be read right now" — call
    /// `readStudentIDData()` where the difference matters.
    public var studentIDData: Data? { readStudentIDData().data }

    public func setStudentIDData(_ data: Data?) throws {
        if let data {
            try secrets.write(data, for: Keys.studentID)
            // The card is committed. A cleanup failure must not report a failed
            // save and cause the caller to restore the previous card's photo.
            try? clearPlaintextStudentID()
            return
        }
        // A blob left by a version that used the plist would otherwise outlive
        // the removal and reappear at the next migration. Keep the keychain copy
        // until every plaintext copy has been cleared successfully.
        try clearPlaintextStudentID()
        try secrets.write(nil, for: Keys.studentID)
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

    /// The remote map URL.
    ///
    /// Read-only: the in-app data-source editor was removed, so there is no
    /// supported way to set this any more. A value left behind by an older
    /// install — or written into the plist by hand — is honoured only if it
    /// still points at an approved source, so a persisted URL cannot redirect
    /// schedule requests somewhere the app would never choose itself.
    public var mapURL: URL {
        guard let raw = defaults.string(forKey: Keys.mapURL),
              let url = URL(string: raw),
              SharedStore.isAllowedSource(url) else {
            return SharedStore.defaultMapURL
        }
        return url
    }

    /// HTTPS, an approved host, no embedded credentials, and the default port.
    public static func isAllowedSource(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              allowedHosts.contains(host),
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return true
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

public enum SharedScheduleDataError: Error { case unavailable }

public struct SharedScheduleData: Sendable {
    public let config: UserConfig
    public let overrides: [DayOverride]
    public let map: DayTypeMap?

    public func resolverInputs(catalog: BellScheduleCatalog) -> ResolverInputs {
        ResolverInputs(map: map,
                       overrides: Dictionary(overrides.map { ($0.day, $0) },
                                             uniquingKeysWith: { _, last in last }),
                       config: config, catalog: catalog)
    }
}
