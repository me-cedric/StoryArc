import Foundation
import Testing

/// That the docked bar labels every action and never takes the screen reader's cursor.
///
/// `ebook-reader`'s *Reaching the transport without touch*: the transport "states what it
/// controls and what is playing, and each of its actions is labelled by what it does",
/// **and** "it does not take focus when it appears, because a session starting must not
/// interrupt what the listener is doing". `audio-playback` says the same of the bar.
///
/// **The second clause is held by an absence, and an absence is what nothing tests.**
/// `PlayerDock.swift`'s own header says so — "there is deliberately no `accessibilityFocused`
/// and no screen-changed announcement in this file. The absence is the feature." Adding one
/// is a two-word edit that reads as a courtesy: *announce the bar when it appears, so a
/// screen-reader user knows it is there*. It compiles, it passes every suite, `swiftlint
/// --strict` and both build gates, and it moves a listener's cursor off the page they were
/// reading every time a book starts speaking. That is the defect, and until this file nothing
/// in the repository would have failed.
///
/// **The positive half is here for the same reason ``ShellWiringTests`` pairs its negatives.**
/// A negative assertion alone is satisfied by deleting the accessibility from the view
/// altogether — a bar with no labels takes no focus. So what must be *present* is asserted
/// beside what must be absent: the containment, the two ways back named by where they go, and
/// the value that carries the title the bar's own truncation eats.
///
/// **What this is not.** It reads Swift source, because `PlayerDock` is a `View` and `swift
/// test` runs on the host with no simulator to compose it in — the reason ``ShellWiringTests``
/// and `ReaderRoutingWiringTests` give at length. It proves a modifier is declared and never
/// what VoiceOver speaks. `read-aloud-beyond-the-reader` task 2.4 owes a VoiceOver walk on a
/// simulator and this does not stand in for it; the task says so itself, in the sentence
/// "verified with the screen reader on, not by reading the code".
///
/// **Proved able to fail**, per AGENTS.md §5, one mutation per half:
/// `@AccessibilityFocusState private var isBarFocused: Bool` on the view failed *The bar never
/// moves the screen reader's cursor* by argument name, and deleting
/// `.accessibilityElement(children: .contain)` from ``PlayerDock/dock(_:)`` failed *Each
/// action is labelled by what it does*. Both were reverted.
@Suite("The dock's focus and labels")
struct PlayerDockFocusTests {

    /// The dock's source, found from this file rather than from the working directory.
    ///
    /// `#filePath` and not a walk up from the process's directory: this repository nests agent
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs looking for a package
    /// root climbs out of the checkout under test and validates the parent repository's copy.
    /// That has happened here before. `#filePath` is fixed at compile time to the source that
    /// was compiled.
    private static let dockSourcePath: String = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/Tests/PlayerFeatureTests/this file → the package root
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        return directory.appendingPathComponent("Sources/PlayerFeature/PlayerDock.swift").path
    }()

    /// The dock's code, comments removed.
    ///
    /// The precision that makes the negative assertion mean anything: the file's header
    /// *names* `accessibilityFocused` and the screen-changed announcement, deliberately,
    /// because recording why they are absent is worth more than their absence alone. A naive
    /// search would fail on the paragraph explaining the rule it guards — the same trap
    /// ``ShellWiringTests/tabDeclarations(in:)`` sidesteps.
    ///
    /// Missing is a failure rather than a skip, and it names the path it looked at. A guard
    /// that cannot find what it guards passes for ever after a rename.
    private func dockCode() throws -> String {
        let path = Self.dockSourcePath
        let text = try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read — has PlayerDock.swift moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
            .joined(separator: "\n")
    }

    @Test(
        "The bar never moves the screen reader's cursor",
        arguments: [
            "accessibilityFocused",
            "AccessibilityFocusState",
            "UIAccessibility.post",
            "AccessibilityNotification",
            ".screenChanged",
            ".layoutChanged",
        ]
    )
    func theBarTakesNoFocus(_ symbol: String) throws {
        #expect(
            !(try dockCode()).contains(symbol),
            """
            PlayerDock.swift names \(symbol) in code. The bar appears the moment a book \
            starts speaking, and ebook-reader's *Reaching the transport without touch* \
            requires that "it does not take focus when it appears, because a session \
            starting must not interrupt what the listener is doing". Moving the cursor \
            there takes a screen-reader user off the page they were reading. If a listener \
            is meant to be told, that is a product change to the requirement, not a \
            modifier.
            """
        )
    }

    @Test(
        "Each action is labelled by what it does, and what is playing is announced in full",
        arguments: [
            // "announced as one element naming what is playing", per audio-playback.
            ".accessibilityElement(children: .contain)",
            // The way back, named by where it goes rather than by what is playing: back to
            // the book for a publication being read aloud, into the player for a narrated
            // file that has no reader to return to.
            "player.back",
            "player.open",
            // The title the bar's own tail truncation eats, announced whole.
            ".accessibilityValue(",
        ]
    )
    func everyActionSaysWhatItDoes(_ declaration: String) throws {
        #expect(
            (try dockCode()).contains(declaration),
            """
            PlayerDock.swift no longer declares \(declaration). The requirement is that the \
            transport "states what it controls and what is playing, and each of its actions \
            is labelled by what it does" — and a bar stripped of its labels would satisfy \
            the focus test above by having nothing left to focus. The two halves are one \
            requirement.
            """
        )
    }
}
