import Foundation
import Testing

/// That the tab bar still has four plain tabs and no search *role*.
///
/// ``LibraryDestinationTests`` pins the *set* — four destinations, in order, unchanged by
/// what a reader configures. It cannot pin the *control*, and the control is the whole point
/// of this change: `navigation-shell` says search "SHALL be a place a reader arrives at, and
/// no control SHALL change shape or position to become it", and `Tab(role: .search)` is
/// precisely a control that changes shape to become it. Adding `role: .search` back to one
/// line of `AppShell.swift` restores the morphing field while the destination set, every
/// `swift test` suite, `swiftlint --strict` and `xcodebuild build` all stay green.
///
/// **So this reads the app's source text, and that is a deliberate second choice**, taken for
/// the reasons ``ReaderRoutingWiringTests`` sets out at length two files away: the app target
/// has no test target of its own, `swift test` runs on the host with no simulator so the
/// `TabView` cannot be composed here, and the only thing in this repository that renders the
/// shell is a UI test on a booted simulator — which no gate runs.
///
/// It is a tripwire, not a proof. It asserts a role is absent and four tabs are present; it
/// never asserts a bar appeared. Delete it the day a `StoryArcUITests` run on a simulator is
/// a gate: that run taps search, lands on a page, and would fail on the restored role by
/// itself.
@Suite("Shell wiring")
struct ShellWiringTests {

    /// The shell's own source, found from this file rather than from the working directory.
    ///
    /// `#filePath` and not a walk up from the process's directory, for the reason
    /// ``ReaderRoutingWiringTests`` records: this repository nests agent worktrees at
    /// `.claude/worktrees/<name>/`, and a walk that climbs looking for `apps/ios/App` climbs
    /// out of the checkout under test and validates the parent repository's copy. That has
    /// happened here. `#filePath` is fixed at compile time to the source that was compiled.
    private static let shellSourcePath: String = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/StoryArcCoreTests/this file → apps/ios
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory.appendingPathComponent("App/AppShell.swift").path
    }()

    /// The shell source's lines, trimmed.
    ///
    /// Missing is a failure rather than a skip, and it names the path it looked at. A guard
    /// that cannot find what it guards passes for ever after a rename.
    private func shellSourceLines() throws -> [String] {
        let path = Self.shellSourcePath
        let text = try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read — has AppShell.swift moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Only lines that declare a tab, so the file's own prose about the role it removed
    /// cannot fail the test that removed it.
    ///
    /// This is the precision that makes the assertion mean anything. `AppShell.swift`'s doc
    /// comment quotes `Tab(role: .search)` at length — deliberately, because the argument it
    /// used to make is worth keeping — and a naive search of the whole file for that string
    /// would fail on the comment while a restored role in a `Tab(...)` call went unnoticed.
    private func tabDeclarations(in lines: [String]) -> [String] {
        lines.filter { $0.hasPrefix("Tab(") }
    }

    @Test("No tab carries the search role")
    func noSearchRole() throws {
        let tabs = tabDeclarations(in: try shellSourceLines())
        #expect(
            !tabs.contains { $0.contains("role:") },
            """
            A tab declares a role again: \(tabs.filter { $0.contains("role:") })
            `Tab(role: .search)` morphs the tab into a field in place, which is the
            shape-changing `navigation-shell` forbids. Search is a destination now.
            """
        )
    }

    @Test("Search is declared as a destination, like its three neighbours")
    func searchIsAPlainTab() throws {
        let tabs = tabDeclarations(in: try shellSourceLines())
        // Without this, deleting the search tab outright would satisfy the test above —
        // the mutation that makes a negative assertion worthless on its own.
        #expect(
            tabs.contains("Tab(value: .destination(.search)) {"),
            """
            The shell no longer declares a plain search tab. Tabs found: \(tabs)
            """
        )
    }

    @Test("Four tabs, one per destination")
    func fourTabs() throws {
        let tabs = tabDeclarations(in: try shellSourceLines())
        #expect(
            tabs.count == 4,
            "Expected four tabs, one per LibraryDestination. Found \(tabs.count): \(tabs)"
        )
        for destination in ["home", "library", "onDevice", "search"] {
            #expect(
                tabs.contains("Tab(value: .destination(.\(destination))) {"),
                "No plain tab for .\(destination). Tabs found: \(tabs)"
            )
        }
    }
}
