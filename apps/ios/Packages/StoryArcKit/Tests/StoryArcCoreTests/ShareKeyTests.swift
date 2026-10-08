import Testing

@testable import StoryArcCore

/// The key a connection and a saved source's locator must agree on, or the detail screen reads
/// an answer nobody wrote (`close-the-audited-gaps` 23.3).
@Suite("Which share a session was with")
struct ShareKeyTests {
    private let nas = ShareKey(host: "nas.local", port: 445, share: "Comics")

    @Test("A locator names the same share as the address it was written from")
    func locatorMatchesAddress() {
        #expect(ShareKey(locator: "smb://nas.local/Comics") == nas)
        #expect(ShareKey(locator: "smb://ada@nas.local/Comics/Series/Deep") == nas)
        #expect(ShareKey(locator: "smb://nas.local:445/Comics") == nas)
    }

    @Test("The port is part of the share")
    func portCounts() {
        #expect(ShareKey(locator: "smb://nas.local:4446/Comics") == ShareKey(host: "nas.local", port: 4446, share: "Comics"))
        #expect(ShareKey(locator: "smb://nas.local:4446/Comics") != nas)
    }

    @Test("Host and share compare without regard to case, and folders below the share do not count")
    func caseAndDepth() {
        #expect(ShareKey(locator: "smb://NAS.local/COMICS/a/b") == nas)
        #expect(ShareKey(locator: "smb://nas.local/Other") != nas)
    }

    @Test("Text that is not a share locator has no key", arguments: [
        "", "https://nas.local/Comics", "smb://", "smb://nas.local", "smb://nas.local:port/Comics",
    ])
    func notALocator(text: String) {
        #expect(ShareKey(locator: text) == nil)
    }
}
