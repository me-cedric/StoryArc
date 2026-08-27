public import Foundation

internal import Security

/// Source secrets, in the Keychain.
///
/// `sources` requires every secret — password, API key or token — to live in "the platform
/// secure store", and requires that a secret is never written to "preferences, logs, crash
/// reports, backups, or exported diagnostics". The registry holds an opaque reference and
/// nothing else, which is what makes that promise structural rather than a habit.
///
/// A generic password item per source, keyed by the source's identifier. Not one item
/// holding a dictionary: removing a source has to remove exactly its own secret, and a
/// shared blob makes that a read, an edit and a write where it should be a delete.
public struct CredentialStore {
    /// Which app the items belong to. A constant rather than the bundle identifier, so a
    /// debug build and a release build read the same items on the same device.
    private let service: String

    public init(service: String = "app.storyarc.sources") {
        self.service = service
    }

    /// The reference a registry entry holds.
    ///
    /// The source's own identifier, and deliberately nothing else. A reference that
    /// encoded anything about the secret would be a fact about the secret stored outside
    /// the secure store.
    public static func reference(for sourceID: UUID) -> String { sourceID.uuidString }

    /// Stores a secret, replacing whatever was there.
    ///
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, which is two promises at once: the
    /// item is unreadable while the device is locked, and `ThisDeviceOnly` keeps it out of
    /// an iCloud Keychain and out of an encrypted backup. `sources` names backups
    /// explicitly.
    @discardableResult
    public func save(_ secret: String, for reference: String) -> Bool {
        guard let data = secret.data(using: .utf8) else { return false }
        remove(reference)

        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Reads a secret at the moment of use.
    ///
    /// Returned rather than cached, per the requirement: "it reads it from the secure store
    /// at the moment of use and does not retain it beyond the request". Nothing in this
    /// type holds one.
    public func secret(for reference: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Forgets one source's secret.
    ///
    /// Called when a source is removed. `sources` requires removal to take "its stored
    /// credentials" with it, and a secret outliving the source it belonged to is a secret
    /// nobody will ever look for again.
    @discardableResult
    public func remove(_ reference: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Whether a secret is stored, without reading it.
    ///
    /// For a source list that shows whether a server is configured. Asking this rather
    /// than calling ``secret(for:)`` and discarding the answer keeps the secret out of
    /// memory for a question that never needed it.
    public func hasSecret(for reference: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
