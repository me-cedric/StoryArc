import Foundation
import Testing

/// That a refresh of one source from its own screen says it is running.
///
/// `sources`' *A refresh of one source from its own screen* is satisfied by one line:
/// `LibraryModel.test(_:)` marks the source `.connecting` **before** it asks, so the detail
/// screen's *Status* row has something true to read for as long as the ask takes. Without
/// the mark the row keeps its last answer and a reader cannot tell a refresh from a screen
/// that is ignoring them.
///
/// **This reads source text, and that is a second choice**, for the reason
/// ``ResumeWiringTests`` records at length: `test(_:)` reaches the network, so nothing in
/// this host suite can call it. Task 8.1 of `a-refresh-that-says-it-is-running` says the
/// function was asserted by nothing on either platform, and this is the tripwire that ends
/// that. Android's `SourceRefreshWiringTest` is the twin.
///
/// It is a tripwire, not a proof. It asserts the mark is written before the ask, never that
/// a server answered.
@Suite("A refresh of one source, from its own screen")
struct SourceRefreshWiringTests {

    /// `apps/ios`, from this file rather than the working directory: this repository nests
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs out validates the
    /// parent checkout instead of the one under test.
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/LibraryFeatureTests/this file → apps/ios
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

    @Test("The source is marked connecting before it is asked")
    func marksBeforeAsking() throws {
        let health = try source("Packages/StoryArcKit/Sources/LibraryFeature/LibrarySourceHealth.swift")

        // **Scoped to the function, not to the file.** `reach(` is called from more than one
        // place in `LibrarySourceHealth.swift`, and an unscoped search found the earlier one
        // and reported the mark as coming after the ask when it comes before it. The slice
        // runs from this function's own signature to the end of the text.
        let signature = try #require(
            health.range(of: "public func test(_ source: Source) async {"),
            "`LibraryModel.test(_:)` is gone or renamed, so the refresh of one source has no entry point"
        )
        let body = String(health[signature.upperBound...])

        let mark = try #require(
            body.range(of: "registry = registry.marking(source.id, as: .connecting)"),
            "`test(_:)` no longer marks the source connecting, so its Status row says nothing while it asks"
        )
        let ask = try #require(
            body.range(of: "let state = await reach("),
            "`test(_:)` no longer reaches the source, so there is nothing to mark it for"
        )
        #expect(
            mark.upperBound < ask.lowerBound,
            "the mark is written after the ask, so the row is only true once the answer is already in"
        )
    }

    @Test("A local folder is answered without a connecting mark")
    func aLocalFolderIsNotConnecting() throws {
        let health = try source("Packages/StoryArcKit/Sources/LibraryFeature/LibrarySourceHealth.swift")

        // A folder is read rather than reached, so *Connecting* would be a claim about a
        // network that is not involved. The guard returns before the mark.
        #expect(
            health.contains("guard SourceProbe.isRemote(source.kind) else {"),
            "`test(_:)` no longer answers a local folder separately, so a folder reads as connecting"
        )
    }
}
