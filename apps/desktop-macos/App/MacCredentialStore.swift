import Foundation
import Persistence
import Security

/// Source secrets on a Mac: which keychain they go to, and the store that writes them.
///
/// `design.md` Decision 2 says `CredentialStore` must set `kSecUseDataProtectionKeychain`
/// on macOS. That keychain needs an application identifier or a keychain access group in
/// the signature, and an ad-hoc build (`CODE_SIGN_IDENTITY=-`, no team) has neither. Task
/// 1.13 measured it rather than assumed it: see `Tests/KeychainSpike.md`. The result picks
/// ``KeychainPath/login`` for every ad-hoc build, and the data-protection path waits for
/// the signed build of task 6.8. ``probeDataProtectionKeychain(service:)`` is the spike,
/// kept callable so the signed build can re-measure and flip the path on evidence.
///
/// On the login path this wrapper delegates to `CredentialStore`, whose queries carry no
/// `kSecUseDataProtectionKeychain` and so land in the login keychain on a Mac. The
/// promises `sources` makes — secret in the system store, never in a file — hold there:
/// the login keychain is the system store, and it lives outside the app's container.
struct MacCredentialStore {
    /// Which keychain a Mac build writes to.
    enum KeychainPath: Equatable, Sendable {
        /// The file-based login keychain. What an ad-hoc build can use.
        case login
        /// The data-protection keychain. Needs a team-signed build; task 6.8.
        case dataProtection
    }

    /// The path picked for this build, by the spike of 2026-10-16.
    static let path: KeychainPath = .login

    private let store: CredentialStore

    init(service: String = "app.storyarc.sources") {
        store = CredentialStore(service: service)
    }

    static func reference(for sourceID: UUID) -> String {
        CredentialStore.reference(for: sourceID)
    }

    @discardableResult
    func save(_ secret: String, for reference: String) -> Bool {
        store.save(secret, for: reference)
    }

    func secret(for reference: String) -> String? {
        store.secret(for: reference)
    }

    @discardableResult
    func remove(_ reference: String) -> Bool {
        store.remove(reference)
    }

    func hasSecret(for reference: String) -> Bool {
        store.hasSecret(for: reference)
    }

    /// The spike: one `SecItemAdd` into the data-protection keychain, and its status.
    ///
    /// The item is removed again when the add succeeds, so a build that can use that
    /// keychain leaves nothing behind. Call it from a test, never from the app: the app
    /// has its answer in ``path``.
    static func probeDataProtectionKeychain(service: String) -> OSStatus {
        let account = "probe-\(UUID().uuidString)"
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data("probe".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecUseDataProtectionKeychain as String: true,
            ]
            SecItemDelete(query as CFDictionary)
        }
        return status
    }
}
