import Foundation
import Security
import Testing

/// The sandbox the Mac app ships with, pinned from both sides.
///
/// Task 1.11 of `desktop-clients`. The file is what Xcode signs into the app, so the first
/// test reads it as a plist and asserts the exact key set: the four `design.md` Decision 2
/// names, and nothing else. A fifth key would be a capability nobody asked for, and a
/// missing one is a feature that fails at the first bookmark. The keychain access group is
/// absent by decision: task 1.13's spike found an ad-hoc build cannot use the
/// data-protection keychain (`KeychainSpike.md`), so no group is declared until task 6.8.
///
/// The second test asks the running process, because the tests are hosted in the app and a
/// file that says *sandbox* proves nothing about a signature that dropped it.
@Suite("Entitlements")
struct EntitlementsTests {
    static let expected: Set<String> = [
        "com.apple.security.app-sandbox",
        "com.apple.security.files.user-selected.read-write",
        "com.apple.security.files.bookmarks.app-scope",
        "com.apple.security.network.client",
    ]

    /// `App/StoryArcMac.entitlements`, copied into the test bundle by `project.yml`: a
    /// test hosted in the sandboxed app cannot read the checkout without a privacy prompt.
    static var file: URL { TestFixtures.entitlements }

    @Test("The file holds exactly the four keys, each true")
    func fileHoldsExactlyTheFourKeys() throws {
        let data = try Data(contentsOf: Self.file)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = try #require(plist as? [String: Any])

        #expect(Set(entitlements.keys) == Self.expected)
        for key in Self.expected {
            #expect(entitlements[key] as? Bool == true, "\(key) must be true")
        }
    }

    @Test("The running app carries each of them")
    func runningAppCarriesThem() throws {
        // Hosted in StoryArc.app, or the question has no answer.
        #expect(Bundle.main.bundleIdentifier == "com.mecedric.storyarc")
        let task = try #require(SecTaskCreateFromSelf(nil))

        for key in Self.expected {
            let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
            #expect(value as? Bool == true, "\(key) is not in the signature")
        }
    }
}
