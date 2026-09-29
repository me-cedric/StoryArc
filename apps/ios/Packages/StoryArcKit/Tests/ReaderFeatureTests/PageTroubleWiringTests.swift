import Foundation
import Testing

/// `decode(_:)` scopes `pageWaitStarted`/`pageFailingSince` to the page on screen, over a
/// share, and only the first failure starts the 60 s clock.
///
/// `network-share`'s *Connection drops while reading*: the notice used to count from a
/// failed read anywhere — a prefetched neighbour's, on a local file same as a share, and
/// every retry restarting the 60 s clock rather than one continuous count from the first
/// failure. `PageRecoveryTests` and `ReaderModelTests` pin what they can reach without a
/// share to fail on cue; this is the one thing left, and it needs exactly that.
///
/// **So this test reads the source text, and that is a deliberate second choice**, for
/// `SmbTransferWiringTests`' reason: driving a real failure over `smb://` and a real success
/// after it needs a share on a schedule this suite does not control. A guard that runs beats
/// a better one that does not.
@Suite("A page's own trouble is scoped to the page on screen, over a share, once")
struct PageTroubleWiringTests {
    private static let source: String = {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = package.appending(path: "Sources/ReaderFeature/ReaderDecoding.swift")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fatalError("ReaderDecoding.swift is not at \(file.path) — has it moved?")
        }
        return text
    }()

    @Test("Only the page on screen, over a share, is tracked")
    func onlyTheCurrentSharePageIsTracked() {
        #expect(
            Self.source.contains(#"index == currentIndex && url.scheme == "smb""#),
            "decode(_:) no longer scopes the network trouble it tracks to the current page over a share."
        )
    }

    @Test("A neighbour's failure, or a local file's, never sets pageWaitStarted")
    func neitherReadNorWriteIsUnconditional() {
        // Every touch of either field goes through `tracksNetwork`, computed once at the
        // top of `decode(_:)` — this is what a regression re-adding an unconditional
        // `pageWaitStarted = Date()` would break, and text is what can say so without a
        // share.
        #expect(Self.source.contains("if tracksNetwork { pageWaitStarted = Date() }"))
        #expect(Self.source.contains("if tracksNetwork { pageWaitStarted = nil }"))
    }

    @Test("Only the first failure starts the 60 s clock")
    func onlyTheFirstFailureStartsTheClock() {
        #expect(
            Self.source.contains("if tracksNetwork, pageFailingSince == nil { pageFailingSince = Date() }"),
            "decode(_:) no longer guards pageFailingSince against a later retry restarting it."
        )
    }
}
