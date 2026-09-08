import Foundation
#if canImport(Security)
import Security
#endif

/// What a secret read found.
///
/// The three cases exist because "not there" and "not readable right now" call
/// for opposite responses: the first means the student has no ID saved and any
/// leftover photo is orphaned, the second means the device is locked and the
/// data must be left exactly where it is until it unlocks.
public enum SecretReadResult: Equatable, Sendable {
    case value(Data)
    case missing
    /// The store exists but cannot be read yet — a locked device, typically.
    case unavailable

    public var data: Data? {
        if case let .value(data) = self { return data }
        return nil
    }
}

/// A place for the handful of bytes that should not sit in a preferences plist.
public protocol SecretStore: Sendable {
    func read(_ key: String) -> SecretReadResult
    /// Writes, or removes when `data` is nil. Throws rather than failing quietly:
    /// a save the student thinks succeeded but did not is worse than an error.
    func write(_ data: Data?, for key: String) throws
}

public struct SecretStoreError: Error, CustomStringConvertible, Equatable {
    public let status: Int32
    public var description: String { "Keychain operation failed (OSStatus \(status))" }
}

/// The Keychain, holding items that are device-only and unavailable while locked.
///
/// `WhenUnlockedThisDeviceOnly` is the point of moving off `UserDefaults`: the
/// item never leaves this device in a backup and is unreadable while the screen
/// is locked, neither of which a preferences plist can claim.
public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = "shankar.Stevenson-Space-Companion-App.secrets") {
        self.service = service
    }

    private func query(_ key: String) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        #if os(macOS)
        // Opts macOS into the same data-protection keychain iOS uses, so
        // `kSecAttrAccessible` means there what it means on the phone.
        query[kSecUseDataProtectionKeychain] = true
        #endif
        return query
    }

    public func read(_ key: String) -> SecretReadResult {
        var query = self.query(key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return (item as? Data).map { .value($0) } ?? .missing
        case errSecItemNotFound:
            return .missing
        default:
            // errSecInteractionNotAllowed and friends: the item may well be
            // there, so the caller must not treat this as an empty store.
            return .unavailable
        }
    }

    public func write(_ data: Data?, for key: String) throws {
        let query = self.query(key)
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecretStoreError(status: status)
            }
            return
        }

        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecretStoreError(status: addStatus) }
        default:
            throw SecretStoreError(status: status)
        }
    }
}

/// A process-lifetime stand-in, so tests never touch the host's real keychain.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data]
    /// Set to simulate a locked device.
    public var isUnavailable = false

    public init(storage: [String: Data] = [:]) {
        self.storage = storage
    }

    public func read(_ key: String) -> SecretReadResult {
        lock.lock()
        defer { lock.unlock() }
        if isUnavailable { return .unavailable }
        return storage[key].map { .value($0) } ?? .missing
    }

    public func write(_ data: Data?, for key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if isUnavailable { throw SecretStoreError(status: errSecInteractionNotAllowed) }
        storage[key] = data
    }
}
