import Foundation
import Testing

/// `SmbSource` drops its session on a network-path change, not only on a failed read.
///
/// `network-share`'s *Network changes*: nothing used to watch for one at all — a stale
/// session was dropped only after a read against it failed, and after ``SmbDeadline`` that
/// still means up to 20 s (or 10 s, for a reopen) of a wait the source already knows is
/// doomed the moment the path moves.
///
/// **So this test reads the source text, and that is a deliberate second choice**, for
/// `SmbTransferWiringTests`' reason. The honest test drives a real `NWPathMonitor` through an
/// actual network change, which nothing on this machine can trigger on demand; `SmbSource`
/// itself is also `private` to `SmbClient.swift`; and the case a live check would still miss —
/// a genuine handover from Wi-Fi to cellular — is not one CI can reach either. A guard that
/// runs beats a better one that does not.
@Suite("A share session drops itself on a network-path change")
struct SmbSourceNetworkChangeWiringTests {

    private static let source: String = {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = package.appending(path: "Sources/Smb/SmbClient.swift")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fatalError("SmbClient.swift is not at \(file.path) — has it moved?")
        }
        return text
    }()

    @Test("The path monitor is started at init and cancelled at deinit")
    func monitorLifecycleIsWired() {
        #expect(Self.source.contains("pathMonitor.start(queue: .global(qos: .utility))"))
        #expect(Self.source.contains("pathMonitor.cancel()"))
    }

    @Test("A path report closes the session through the actor, not directly on the reader")
    func reportReachesTheActor() {
        #expect(
            Self.source.contains("Task { await self.noteNetworkChange() }"),
            "the path monitor's handler no longer hops onto the actor to drop the session"
        )
    }

    @Test("The monitor's own opening report is not read as a change")
    func firstReportIsSkipped() {
        // NWPathMonitor calls its handler once immediately with the path already in effect.
        // Without this guard, opening any share would drop its own brand-new session before
        // the first read ever used it.
        #expect(Self.source.contains("guard hasSeenFirstPath else"))
    }
}
