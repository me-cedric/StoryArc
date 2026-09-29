import Foundation
import Testing

/// That the app's keep-for-offline copy is named by the download store, read in chunks, and
/// recorded.
///
/// `KeptCopyLocationTests`, `ChunkedCopyTests` and `DownloadFinishedCopyTests` pin the three
/// rules. The wiring lives in the app target, which has no test target of its own, so this
/// reads its source text — the second choice `ReaderRoutingWiringTests` explains. Android's
/// `KeepForOfflineWiringTest` is the same guard.
@Suite("Keep for offline wiring")
struct KeepForOfflineWiringTests {
    /// An app source file with its comment lines left out, so an explanation of the old
    /// defect does not read as the defect.
    private static func app(_ name: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/StoryArcCoreTests/this file
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        let path = directory.appendingPathComponent("App/\(name)").path
        let text = try #require(try? String(contentsOfFile: path, encoding: .utf8), "\(path) could not be read")
        return text
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    @Test("The copy is named by the download store, never by the server")
    func namedByTheStore() throws {
        let source = try Self.app("KeepForOffline.swift")
        #expect(source.contains("DownloadStore.location("))
        #expect(!source.contains("lastPathComponent"), "the kept copy is named from the server's own path again")
    }

    @Test("The copy is read in chunks rather than in one read")
    func readInChunks() throws {
        let source = try Self.app("KeepForOffline.swift")
        #expect(source.contains("ChunkedCopy.copy("))
        #expect(!source.contains("read(offset: 0"))
    }

    @Test("A finished copy is recorded as a download")
    func recorded() throws {
        let source = try Self.app("StoryArcAppActions.swift")
        #expect(source.contains("Download.finishedCopy("))
    }
}
