import Foundation
import Testing

/// Task 2.9's corrected note: `ServerLibrary`'s per-source refresh already called
/// `KavitaSync.pull`, and it already discarded what came back — so a conflict a background
/// refresh resolved never reached a reader, where the series screen's own pull reaches
/// `SyncConflictNotice` for the same kind of conflict.
///
/// Read as source, for the reason `WhatsNewWiringTests` gives: `swift test` runs on the host
/// with no simulator, so a `LibraryView` cannot be composed here to prove what it mounts.
@Suite("ServerLibrary conflict wiring")
struct ServerLibraryConflictWiringTests {

    /// `apps/ios`, found from this file rather than from the working directory. See
    /// `WhatsNewWiringTests` for why a walk up from the process directory is refused.
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

    @Test("A Kavita source's own refresh keeps what its pull found, rather than throwing it away")
    func pullConflictsAreCollected() throws {
        let serverLibrary = try source("Packages/StoryArcKit/Sources/LibraryFeature/ServerLibrary.swift")
        #expect(
            serverLibrary.contains("conflicts += await KavitaSync.pull("),
            "ServerLibrary's Kavita branch no longer collects KavitaSync.pull's conflicts."
        )
        #expect(
            serverLibrary.contains("RefreshConflicts.shared.report(reading.conflicts)"),
            "readServers() no longer reports what a refresh found to RefreshConflicts."
        )
    }

    @Test("The library view mounts the notice, or a background refresh's conflict is never shown")
    func viewMountsNotice() throws {
        let view = try source("Packages/StoryArcKit/Sources/LibraryFeature/LibraryView.swift")
        #expect(
            view.contains(".refreshConflictNotice(progress: progress)"),
            "LibraryView no longer mounts refreshConflictNotice."
        )
    }
}
