import Foundation
import Testing

/// That the app actually routes on ``Publication/isReflowable``, and routes the right way
/// round.
///
/// ``IsReflowableTests`` pins the *rule* — which publications the reflowable reader is for.
/// It cannot pin the *wiring*, and the wiring is the whole reason the property exists.
/// `StoryArcApp` chooses between `EpubReaderView` and `ReaderView` in a view body, and
/// **inverting that one condition sends every reflowable EPUB to the comic reader and every
/// comic to the EPUB reader while `swift test`, `swiftlint --strict`, `xcodebuild build` and
/// `pnpm lint` all stay green.** That was measured, not imagined: the suite that named
/// itself after this routing survived exactly that edit.
///
/// **So this test reads the app's source text, and that is a deliberate second choice.** The
/// honest test renders the cover and asks which reader came up, and no unit test can do
/// that: the app target has no test target of its own, the two reader views live in packages
/// that do not depend on each other (`EpubReaderFeature` cannot see `ReaderFeature`, by the
/// module rule in `docs/architecture`), and the only thing in this repository that renders
/// the app is a UI test on a booted simulator — which no gate runs. A tripwire that runs in
/// `pnpm test:ios` guards the path the next hand actually takes.
///
/// It is a tripwire, not a proof. It asserts the condition is spelled correctly and the two
/// branches are in the right order; it never asserts that a book appeared. Its Android
/// counterpart is `ReaderChromeWiringTest`, written for the same reason and carrying the same
/// warning, and `scripts/line-cap.mjs` is the same kind of gate again.
///
/// Delete this the day a run of `StoryArcUITests` on a simulator is a gate: that run opens
/// both readers and would fail on the inversion by itself.
@Suite("Reader routing wiring")
struct ReaderRoutingWiringTests {

    /// The app's own source, found from this file rather than from the working directory.
    ///
    /// `#filePath` and not a walk up from the process's directory. This repository nests
    /// agent worktrees at `.claude/worktrees/<name>/`, and a walk that climbs until it finds
    /// `apps/ios/App` climbs out of the checkout under test and validates the parent
    /// repository's copy — which is how the Android counterpart of this test came to pass
    /// against a file that was never built. `#filePath` is fixed at compile time to the
    /// source that was compiled, so it cannot leave the checkout it belongs to.
    private static let appSourcePath: String = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/StoryArcCoreTests/this file
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory.appendingPathComponent("App/StoryArcApp.swift").path
    }()

    /// The app source's lines, trimmed, with empty ones dropped.
    ///
    /// Missing is a failure rather than a skip, and it names the path it looked at. A guard
    /// that cannot find what it guards has to say so, or it passes for ever after a rename.
    private func appSourceLines() throws -> [String] {
        let path = Self.appSourcePath
        let text = try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read — has StoryArcApp.swift moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    @Test("The reader cover branches on isReflowable, and only on that")
    func routesOnTheProperty() throws {
        let lines = try appSourceLines()

        // The exact spelling, because the mutation that survived was one `!` away from it.
        #expect(
            lines.filter { $0 == "if selection.publication.isReflowable {" }.count == 1,
            """
            StoryArcApp.swift no longer contains exactly one \
            `if selection.publication.isReflowable {`. If the routing moved, \
            move this guard with it.
            """
        )

        // Once, so a negated copy or a second branch cannot ride alongside the first.
        #expect(
            lines.filter { $0.contains("isReflowable") }.count == 1,
            "StoryArcApp.swift mentions `isReflowable` more than once."
        )

        // The property is the whole point: re-deriving the rule from the format in the view
        // body is the defect it was extracted to end.
        #expect(!lines.contains { $0.contains("isFixedLayout") })
        #expect(!lines.contains { $0.contains("format == .epub") })
    }

    @Test("The reflowable branch builds the EPUB reader and the other builds the comic one")
    func branchesAreNotSwapped() throws {
        let lines = try appSourceLines()
        // Bound to a local before `#require` sees it: the macro reports the whole
        // expression it evaluated, and `lines.firstIndex(of:)` puts the entire app source
        // in the failure message.
        let condition = lines.firstIndex(of: "if selection.publication.isReflowable {")
        let routing = try #require(
            condition,
            "The routing condition is not in StoryArcApp.swift at all."
        )

        // Spelling the condition correctly and swapping the two bodies is the same defect
        // with the same symptom, and the check above cannot see it.
        #expect(
            lines[routing + 1] == "EpubReaderView(",
            """
            The line after the routing condition is `\(lines[routing + 1])`, \
            not `EpubReaderView(`.
            """
        )

        let nextElse = lines[routing...].firstIndex(of: "} else {")
        let otherwise = try #require(
            nextElse,
            "The routing condition has no `} else {` after it."
        )
        #expect(
            lines[otherwise + 1] == "ReaderView(",
            """
            The line after the routing condition's `} else {` is \
            `\(lines[otherwise + 1])`, not `ReaderView(`.
            """
        )
    }
}
