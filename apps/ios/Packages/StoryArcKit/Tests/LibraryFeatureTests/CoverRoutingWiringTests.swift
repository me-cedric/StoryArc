import Foundation
import Testing

/// Every surface that shows a publication leads to its page.
///
/// `publication-detail` requires the page reachable "from every surface that shows a
/// publication", and four iOS surfaces were gating the link so that the publications with the
/// most to explain could not reach it:
///
/// - `CoverCell` and `CoverList` gated on `publication.isOpenable`, so a comic no decoder can
///   open was not tappable. Android had already removed exactly this gate.
/// - `HomeRow` gated on `isReadableNow`, so a dimmed card led nowhere — while the same
///   publication in the library's grid was tappable.
/// - `ReadingListDetail`'s row opened the **reader**, where Android's opens the page.
///
/// Each argued itself at the time: the caption already names the refusal, so the page would be
/// "a second place to read the same refusal". It is not a second place. `DetailActions` draws
/// **no primary action at all** for a publication nothing can open — `primary` returns
/// `EmptyView` — and states the named refusal under it. That is the screen that answers "why
/// can I not open this", and a cover that leads nowhere answers nothing.
///
/// **This reads source text, and that wants justifying.** What is worth pinning is a property
/// of the *call sites*, and a test of a view's behaviour cannot see who declined to link to it.
/// `swift test` runs on the host with no simulator, so composing these views is not available
/// to this gate; `ReaderRoutingWiringTests` in `StoryArcCoreTests` makes the same trade for the
/// same reason and explains it at length. Delete this the day a `StoryArcUITests` run on a
/// simulator is a gate — that run taps a refused cover and would fail on a re-added gate by
/// itself.
@Suite("Cover routing wiring")
struct CoverRoutingWiringTests {

    /// The feature's own sources, found from this file rather than from the process directory.
    ///
    /// `#filePath`, not a walk up from the working directory: this repository nests agent
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs looking for a known
    /// folder climbs out of the checkout under test and validates the parent repository's copy.
    /// That has happened here before. `#filePath` is fixed at compile time to the source that
    /// was compiled, so it cannot leave its own checkout.
    private static func source(_ name: String) -> String {
        var directory = URL(fileURLWithPath: #filePath)
        // …/Packages/StoryArcKit/Tests/LibraryFeatureTests/this file → StoryArcKit
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        return directory
            .appendingPathComponent("Sources/LibraryFeature/\(name)")
            .path
    }

    private func lines(of name: String) throws -> [String] {
        let path = Self.source(name)
        let text = try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read — has \(name) moved? A guard that cannot find what it guards passes for ever."
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The three cover surfaces link on the picking state alone, and on nothing about the
    /// publication.
    ///
    /// Only the `if` **immediately above the link** is examined, and that precision is the
    /// whole test. Both `isOpenable` and `isReadableNow` are legitimate questions elsewhere in
    /// these same files — they decide a caption and a dim, and must go on doing so. A first
    /// version of this checked every `if` in the file and failed on `CoverList`'s caption.
    @Test(
        "No cover surface gates its link on what the publication can do",
        arguments: ["CoverCell.swift", "CoverList.swift", "HomeRow.swift"]
    )
    func linksAreNotGated(file: String) throws {
        let all = try lines(of: file)
        let link = try #require(
            all.firstIndex { $0.contains("NavigationLink(value: PublicationRoute(") },
            "\(file) has no publication link to examine."
        )
        // The nearest `if` above it, or none at all when the link is unconditional.
        guard let guardLine = all[..<link].last(where: { $0.hasPrefix("if ") && $0.hasSuffix("{") })
        else { return }

        #expect(
            !guardLine.contains("publication.isOpenable"),
            """
            \(file) gates its link on isOpenable again: \(guardLine)
            The page is where a refusal is explained.
            """
        )
        #expect(
            !guardLine.contains("isReadable"),
            """
            \(file) gates its link on readability again: \(guardLine)
            A dimmed cover still has a page to explain itself.
            """
        )
    }

    /// The three cover surfaces still carry a link at all.
    ///
    /// Without this, deleting the `NavigationLink` outright would satisfy the test above —
    /// which is the mutation that makes a negative assertion worthless on its own.
    @Test(
        "Every cover surface still links to the publication's page",
        arguments: ["CoverCell.swift", "CoverList.swift", "HomeRow.swift"]
    )
    func linksExist(file: String) throws {
        let text = try lines(of: file).joined(separator: "\n")
        #expect(
            text.contains("NavigationLink(value: PublicationRoute("),
            "\(file) no longer links to a publication page at all."
        )
    }

    /// A reading list's row leads to the page, not into the reader.
    ///
    /// The rule's exception is a **resume affordance**, and this row is not one: a number, a
    /// title and a finished mark, with no cover, no progress and no *Continue* wording. Nothing
    /// about it says the reader has decided to read this one now, so opening the reader was the
    /// app deciding for them. Android's equivalent already opened the page.
    @Test("A reading list's row opens the page rather than the reader")
    func readingListRowOpensThePage() throws {
        let text = try lines(of: "ShelfDetail.swift").joined(separator: "\n")
        #expect(
            text.contains("NavigationLink(value: publication.map(PublicationRoute.init))"),
            "ShelfDetail's row no longer links to the publication page."
        )
        #expect(
            !text.contains("onOpen(publication, url)"),
            "ShelfDetail's row opens the reader again, which makes the decision for the reader."
        )
    }
}
