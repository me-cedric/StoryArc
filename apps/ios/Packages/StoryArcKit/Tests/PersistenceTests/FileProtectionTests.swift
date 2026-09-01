import Foundation
import Testing

@testable import Persistence

/// What the app writes is protected at rest, not merely hidden from backups.
///
/// The security review's rank 18: nothing the app wrote named a protection
/// class, so every downloaded publication sat at the system default,
/// `CompleteUntilFirstUserAuthentication` — readable off a locked device that
/// has been unlocked once since boot. The credentials that fetched those files
/// were already pinned to `WhenUnlockedThisDeviceOnly`, so the reader's books
/// were protected more weakly than the passwords for them.
///
/// Asserted on the host, which is not iOS. macOS stores and reports the same
/// attribute without enforcing it, so what these tests prove is that the class
/// is *asked for* on the directory the files land in — the part that is ours.
/// The enforcement is the kernel's.
@Suite("File protection")
struct FileProtectionTests {

    private let directory = URL.temporaryDirectory
        .appending(path: "protection-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func store() -> DownloadStore {
        DownloadStore(defaults: freshDefaults(), directory: directory)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "protection-\(UUID().uuidString)")
        return suite ?? .standard
    }

    @Test("The downloads directory is created under a protection class")
    func downloadsDirectoryIsProtected() throws {
        let store = store()
        try store.prepare()
        defer { try? FileManager.default.removeItem(at: directory) }

        try expectDownloadProtection(of: directory, is: DownloadStore.fileProtection)
    }

    /// Not `.complete`, and the reason is a requirement rather than a preference.
    ///
    /// `offline-downloads` promises a backgrounded download "continues under the
    /// platform's background transfer mechanism". The system wakes the app to
    /// hand over a finished transfer whether or not the device has been unlocked
    /// since, and a `.complete` destination cannot have a file created in it
    /// then — the download would be lost at the last step, silently.
    @Test("The class is the one a background transfer can still write into")
    func theClassAllowsABackgroundTransferToLand() {
        #expect(DownloadStore.fileProtection == .completeUnlessOpen)
    }

    @Test("Clearing downloads leaves the directory protected, not merely re-made")
    func clearingKeepsTheProtection() throws {
        let store = store()
        try store.prepare()
        defer { try? FileManager.default.removeItem(at: directory) }

        // `clearing()` deletes the directory and re-makes it. A re-made directory
        // carries neither the backup exclusion nor the protection class unless
        // the re-making asks for both.
        _ = store.clearing()

        try expectDownloadProtection(of: directory, is: DownloadStore.fileProtection)
    }
}

/// Asserts the directory carries the data-protection class the app asks for, where the platform
/// has one.
///
/// **The `#if` is the assertion on macOS, not a hole in it.** Data protection is an iOS facility;
/// on macOS the attribute is accepted and then makes every file written under it unreadable to
/// the process that wrote it, so the stores apply it on iOS only. Asserting its *absence* here
/// pins that guard from both sides — deleting the `#if os(iOS)` in the store fails this on the
/// host, and deleting the store's `setAttributes` altogether fails it on a device.
func expectDownloadProtection(of directory: URL, is expected: FileProtectionType) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    #if os(iOS)
    #expect(attributes[.protectionKey] as? FileProtectionType == expected)
    #else
    // The message is one literal because `#expect`'s comment is a `Comment?`, which is
    // expressible by a string literal and not by a concatenation.
    #expect(
        attributes[.protectionKey] == nil,
        "macOS must carry no protection class: it makes the file unreadable to its own writer."
    )
    #endif
}
