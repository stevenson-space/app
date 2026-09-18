import Foundation
import Testing
@testable import ScheduleKit

private final class ScheduleReadingDefaults: UserDefaults, @unchecked Sendable {
    var requestedKeys: [String] = []
    override func object(forKey defaultName: String) -> Any? {
        requestedKeys.append(defaultName)
        return super.object(forKey: defaultName)
    }
}

private struct WidgetMigrationRefusingSecrets: SecretStore {
    func read(_ key: String) -> SecretReadResult { .missing }
    func write(_ data: Data?, for key: String) throws { throw SecretStoreError(status: -34018) }
}

@Suite struct WidgetStorageTests {
    @Test func readerOnlyReadsScheduleKeysAndNeverMigratesIdentity() throws {
        let name = "widget-reader-\(UUID())"
        let defaults = try #require(ScheduleReadingDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "sk.widgetDataReady")
        defaults.set(Data("private student ID".utf8), forKey: "sk.studentID")
        var config = UserConfig(freePeriods: [6, 7])
        config.customizations["2"] = PeriodCustomization(name: "Biology", room: "243", emoji: "🧫")
        config.timeFormat = .twentyFourHour
        defaults.set(try JSONEncoder().encode(config), forKey: "sk.userConfig")
        let override = DayOverride(day: day(2026, 9, 14), type: .asynchronous)
        defaults.set(try JSONEncoder().encode([override]), forKey: "sk.overrides")
        defaults.set(Data(#"{"Late Arrival":["9/18/2026"]}"#.utf8), forKey: "sk.mapData")
        let before = defaults.persistentDomain(forName: name)! as NSDictionary
        defaults.requestedKeys = []
        let data = try SharedStore.readScheduleData(from: defaults)
        #expect(data.config == config)
        #expect(data.overrides == [override])
        #expect(data.map != nil)
        let allowed: Set<String> = ["sk.widgetDataReady", "sk.userConfig", "sk.overrides", "sk.mapData"]
        #expect(Set(defaults.requestedKeys).isSubset(of: allowed))
        #expect(!defaults.requestedKeys.contains("sk.studentID"))
        #expect(before == defaults.persistentDomain(forName: name)! as NSDictionary)
    }

    @Test func missingConfigAndCacheAreDefaultsButUninitializedOrCorruptDataAreUnavailable() throws {
        let name = "widget-defaults-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(throws: (any Error).self) { try SharedStore.readScheduleData(from: defaults) }
        defaults.set(true, forKey: "sk.widgetDataReady")
        let data = try SharedStore.readScheduleData(from: defaults)
        #expect(data.config == UserConfig())
        #expect(data.map == nil)
        let timeline = resolveDay(day(2026, 9, 14), inputs: data.resolverInputs(catalog: TestSupport.catalog))
        #expect(timeline.blocks.count == 8)
        defaults.set(Data("broken".utf8), forKey: "sk.mapData")
        #expect(throws: (any Error).self) { try SharedStore.readScheduleData(from: defaults) }
        defaults.removeObject(forKey: "sk.mapData")
        defaults.set(Data("broken".utf8), forKey: "sk.userConfig")
        #expect(throws: (any Error).self) { try SharedStore.readScheduleData(from: defaults) }
    }

    @Test func enablingGroupPreservesPrivateSuiteSettingsAndCaches() throws {
        let name = "widget-migration-\(UUID())"
        let legacyName = "widget-migration-standard-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        let legacy = try #require(UserDefaults(suiteName: legacyName))
        let secrets = InMemorySecretStore()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID()).plist")
        defer {
            defaults.removePersistentDomain(forName: name)
            legacy.removePersistentDomain(forName: legacyName)
            try? FileManager.default.removeItem(at: file)
        }
        let config = UserConfig(freePeriods: [6, 7], timeFormat: .twentyFourHour)
        let override = DayOverride(day: day(2026, 9, 18), type: .noSchool)
        let map = Data(#"{"Late Arrival":["9/18/2026"]}"#.utf8)
        let metadata = FetchMetadata(lastSuccess: Date(timeIntervalSince1970: 100))
        let identity = Data("student ID".utf8)
        let values: [String: Any] = [
            "sk.userConfig": try JSONEncoder().encode(config),
            "sk.overrides": try JSONEncoder().encode([override]),
            "sk.mapData": map,
            "sk.fetchMetadata": try JSONEncoder().encode(metadata),
            "sk.notificationPrefs": try JSONEncoder().encode(NotificationPrefs(blockEndEnabled: true)),
            "sk.lunchMenuData": Data("old lunch cache".utf8),
            "sk.studentID": identity,
            "sk.studentIDPhotoHidden": true,
            "sk.migratedToAppGroup": true,
        ]
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0).write(to: file)
        legacy.set(try JSONEncoder().encode(UserConfig()), forKey: "sk.userConfig")
        let store = SharedStore(defaults: defaults, secrets: secrets, legacyDefaults: legacy)
        store.migrateFromPrivateSuiteIfNeeded(fileURL: file)
        store.migrateFromStandardIfNeeded()
        #expect(store.userConfig == config)
        #expect(store.overrides == [override])
        #expect(store.cachedMapData == map)
        #expect(store.fetchMetadata == metadata)
        #expect(store.notificationPrefs.blockEndEnabled)
        #expect(store.cachedLunchMenuData == Data("old lunch cache".utf8))
        #expect(store.studentIDPhotoHidden)
        #expect(secrets.read("sk.studentID") == .value(identity))
        #expect(defaults.data(forKey: "sk.studentID") == nil)
        let cleaned = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as! [String: Any]
        #expect(cleaned["sk.studentID"] == nil)
        // New edits must survive later launches; the old file is never replayed.
        store.userConfig = UserConfig(freePeriods: [1])
        store.migrateFromPrivateSuiteIfNeeded(fileURL: file)
        #expect(store.userConfig.freePeriods == [1])
    }

    @Test func missingPrivateFileRetriesAndDoesNotReplaceSharedValues() throws {
        let name = "widget-retry-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID()).plist")
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: file)
        }
        let store = SharedStore(defaults: defaults, secrets: InMemorySecretStore(), legacyDefaults: defaults)
        store.migrateFromPrivateSuiteIfNeeded(fileURL: file)
        #expect(!defaults.bool(forKey: "sk.privateSuiteMigrated"))
        store.userConfig = UserConfig(freePeriods: [8])
        let values = ["sk.userConfig": try JSONEncoder().encode(UserConfig()),
                      "sk.mapData": Data(#"{"Late Arrival":["9/18/2026"]}"#.utf8)]
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0).write(to: file)
        store.migrateFromPrivateSuiteIfNeeded(fileURL: file)
        #expect(store.userConfig.freePeriods == [8])
        #expect(store.cachedMapData == values["sk.mapData"])
    }

    @Test func failedIdentityMigrationStillServesThePrivateCard() throws {
        let name = "widget-identity-retry-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID()).plist")
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: file)
        }
        let identity = Data("legacy identity".utf8)
        let values = ["sk.studentID": identity]
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0).write(to: file)
        let store = SharedStore(defaults: defaults, secrets: WidgetMigrationRefusingSecrets(), legacyDefaults: defaults)
        store.migrateFromPrivateSuiteIfNeeded(fileURL: file)
        // A failed keychain write must not turn an existing card into "missing"
        // and trigger the app's orphan-photo cleanup.
        #expect(store.readStudentIDData() == .value(identity))
        #expect(defaults.data(forKey: "sk.studentID") == nil)
        #expect(!defaults.bool(forKey: "sk.privateSuiteMigrated"))
    }

    @Test func freshSnapshotsSeeConfigurationAndOverrideChanges() throws {
        let name = "widget-reload-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "sk.widgetDataReady")
        let store = SharedStore(defaults: defaults, secrets: InMemorySecretStore(), legacyDefaults: defaults)
        let date = day(2026, 9, 14)
        func current() throws -> WidgetScheduleEntry {
            let data = try SharedStore.readScheduleData(from: defaults)
            return WidgetTimelinePlanner.plan(from: TestSupport.at(date, 9, 0),
                inputs: data.resolverInputs(catalog: TestSupport.catalog)).entries[0]
        }
        #expect(try current().focus?.role == .classPeriod)
        store.userConfig = UserConfig(freePeriods: [1])
        #expect(try current().focus?.role == .free)
        store.overrides = [DayOverride(day: date, type: .asynchronous)]
        #expect(try current().state == .asynchronous)
        #expect(try current().countdownInterval == nil)
    }
}
