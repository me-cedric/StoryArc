import Foundation
import Security
import Testing

@testable import StoryArc

/// Secrets on a Mac, task 1.13 of `desktop-clients`.
///
/// Three tests. The spike pins what an ad-hoc build gets from the data-protection
/// keychain, so the day a signed build changes the answer this fails by name and the path
/// is flipped on evidence rather than on a date. The other two are the task's: a secret
/// saved on the chosen path reads back, and no file in the app's container holds it.
@Suite("Mac credential store")
struct MacCredentialStoreTests {
    private func service() -> String { "app.storyarc.mac.tests.\(UUID().uuidString)" }

    @Test("Spike: an ad-hoc build cannot add to the data-protection keychain")
    func dataProtectionKeychainRefusesAnAdHocBuild() {
        let status = MacCredentialStore.probeDataProtectionKeychain(service: service())

        #expect(
            status == errSecMissingEntitlement,
            "SecItemAdd with kSecUseDataProtectionKeychain returned \(status); the spike expected -34018"
        )
        #expect(MacCredentialStore.path == .login)
    }

    @Test("A secret saved on the chosen path reads back, and leaves with its source")
    func roundTrip() {
        let store = MacCredentialStore(service: service())
        let reference = MacCredentialStore.reference(for: UUID())
        let secret = "s-\(UUID().uuidString)"

        #expect(store.save(secret, for: reference))
        #expect(store.secret(for: reference) == secret)
        #expect(store.hasSecret(for: reference))

        #expect(store.remove(reference))
        #expect(store.secret(for: reference) == nil)
    }

    @Test("No file in the app's container holds a saved secret, in any encoding")
    func secretIsAbsentFromTheContainer() throws {
        // The host is the sandboxed app, or home is the real home directory and the scan
        // below is both endless and meaningless. Fail loudly rather than pass vacuously.
        let environment = ProcessInfo.processInfo.environment
        _ = try #require(environment["APP_SANDBOX_CONTAINER_ID"], "not running in the sandboxed app")
        let home = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)

        let store = MacCredentialStore(service: service())
        let reference = MacCredentialStore.reference(for: UUID())
        let secret = "secret-\(UUID().uuidString)"
        #expect(store.save(secret, for: reference))
        defer { store.remove(reference) }

        let needles = Self.encodings(of: secret)
        var scanned = 0
        var hits: [String] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let files = FileManager.default.enumerator(at: home, includingPropertiesForKeys: keys)
        while let url = files?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) <= Self.largestFileScanned else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            scanned += 1
            if needles.contains(where: { data.range(of: $0) != nil }) { hits.append(url.path()) }
        }

        #expect(hits.isEmpty, "the secret is in: \(hits)")
        // The container is never empty once a test has run: defaults and caches live there.
        #expect(scanned > 0, "no file was scanned under \(home.path())")
    }

    /// Files larger than this are not a preference, a log or a diagnostic.
    private static let largestFileScanned = 64 * 1024 * 1024

    /// The secret as UTF-8, UTF-16 in both byte orders, and base64 of the UTF-8.
    private static func encodings(of secret: String) -> [Data] {
        let utf8 = Data(secret.utf8)
        return [
            utf8,
            Data(secret.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }),
            Data(secret.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }),
            Data(utf8.base64EncodedString().utf8),
        ]
    }
}
