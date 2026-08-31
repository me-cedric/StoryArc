import Foundation
import Testing

@testable import SettingsFeature

/// The source detail screen says when a source cannot hold a reading position.
///
/// `reading-progress`' *Source cannot store progress*: "progress is kept locally only, and
/// the source detail screen states that progress for it does not sync". Which sources have a
/// mechanism is ``StoryArcCore/SourceKind/syncsReadingProgress``' answer and is asserted
/// beside it in `StoryArcCoreTests`; what is asserted here is that this screen asks the
/// question at all, because a test of the predicate alone stays green when the row is deleted
/// from the view — which is the state the app was already in.
///
/// **Read out of the source rather than composed.** Android answers this by composing
/// `SourceDetailScreen` under Robolectric and looking for the sentence; there is no
/// equivalent here. `pnpm test:ios` runs on the host with no simulator, and swift-testing has
/// no way to inspect a rendered SwiftUI hierarchy — so the only thing left that fails when
/// the row goes is the text of the file that draws it. It is a weaker proof than Android's
/// and it is named as one: it shows the lookup is written under the condition, not that a
/// reader saw it. The screenshot AGENTS.md §6 asks for is what closes that gap.
@Suite("The iOS source detail screen states when progress stays local")
struct SourceProgressNoteTests {

    /// `SourceDetail.swift`, found from this file rather than from the working directory.
    ///
    /// The mistake `fix(android): the reader's wiring guard reads the file it is guarding`
    /// paid for: a guard that walks up from the process's directory climbs out of an agent
    /// worktree nested at `.claude/worktrees/<name>/` and validates the parent checkout's
    /// copy — passing on a file that was never built. `#filePath` is this test's own location
    /// inside the package, so the two `..` below cannot leave it.
    private static var drawnBy: String {
        get throws {
            let tests = URL(filePath: #filePath).deletingLastPathComponent()
            let view = tests
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/SettingsFeature/SourceDetail.swift")
            try #require(
                FileManager.default.fileExists(atPath: view.path),
                "\(view.path) is not there — has SourceDetail.swift moved?"
            )
            return try String(contentsOf: view, encoding: .utf8)
        }
    }

    @Test("The sentence is looked up, and only where a source cannot hold a position")
    func theNoteIsDrawnUnderItsCondition() throws {
        let source = try Self.drawnBy

        #expect(source.contains(#"Text("sources.detail.progressLocalOnly", bundle: .module)"#))
        // Negated, and that is the whole claim: shown on every source the sentence would be
        // no information, and on Kavita — the one source that does sync — it would be false.
        #expect(source.contains("if !source.kind.syncsReadingProgress {"))
    }
}
