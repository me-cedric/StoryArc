import Foundation
import Testing

/// `collections-and-reading-lists` task 7.5: "pushed on reconnection" used to mean only the
/// screen that happened to be open when a server came back. `SourceHealth.probe`'s own
/// reason — in `LibrarySourceHealth.swift`'s header — is why this reads source rather than
/// driving a real reconnection. Android's `SourceRetryWiringTest` makes the same claims.
@Suite("Queued shelf edits reach the server on reconnection")
struct SourceRetryWiringTests {

    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.appleRoot.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    private func probeNetworkSourcesBody() throws -> String {
        let health = try source("Packages/StoryArcKit/Sources/LibraryFeature/LibrarySourceHealth.swift")
        let start = try #require(
            health.range(of: "func probeNetworkSources("),
            "LibrarySourceHealth.swift no longer has probeNetworkSources"
        )
        let end = health.range(of: "\n    func probe(", range: start.upperBound..<health.endIndex)
        return String(health[start.upperBound..<(end?.lowerBound ?? health.endIndex)])
    }

    @Test("A source that just answered reconciles and flushes through one call")
    func reconcilesAndFlushes() throws {
        let body = try probeNetworkSourcesBody()
        #expect(
            body.contains("await reconcileAndFlush(fetched.listCapable)"),
            "probeNetworkSources no longer asks reconcileAndFlush to run for a source that just answered."
        )
    }

    @Test("reconcileAndFlush both reconciles and flushes every answering source")
    func reconcileAndFlushDoesBoth() throws {
        let health = try source("Packages/StoryArcKit/Sources/LibraryFeature/ShelfOrderConflict.swift")
        let start = try #require(
            health.range(of: "func reconcileAndFlush("),
            "ShelfOrderConflict.swift no longer has reconcileAndFlush"
        )
        let body = String(health[start.upperBound...])

        #expect(
            body.contains("await ShelfSync.reconcile("),
            "reconcileAndFlush no longer reconciles, so an edit queued while away is never merged in."
        )
        #expect(
            body.contains("await KavitaSync.flush("),
            "reconcileAndFlush no longer flushes on its own, so a held reorder with no owed append waits."
        )
        let reconcile = body.range(of: "await ShelfSync.reconcile(")
        let flush = body.range(of: "await KavitaSync.flush(")
        if let reconcile, let flush {
            #expect(
                reconcile.lowerBound < flush.lowerBound,
                "the flush and the reconcile are not both present in the order task 7.5 asks for"
            )
        }
    }

    @Test("A stale order found on reconnection still writes the conflict notice")
    func staleOrderStillNotices() throws {
        let health = try source("Packages/StoryArcKit/Sources/LibraryFeature/ShelfOrderConflict.swift")
        #expect(
            health.contains("onOrderConflict: { listID in"),
            "the flush on reconnection no longer passes onOrderConflict, so task 7.4's guard is skipped here."
        )
        #expect(
            health.contains("KavitaSync.noteOrderConflict("),
            "a stale order found on reconnection no longer notes a ShelfConflictNotice."
        )
    }
}
