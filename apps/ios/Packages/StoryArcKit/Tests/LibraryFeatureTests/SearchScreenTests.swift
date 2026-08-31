import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What the search screen offers before a letter is typed.
///
/// `navigation-shell`'s *What search opens onto*: the screen presents "publications the
/// reader already has — at least one in progress, one never opened, and one that is next in
/// a series they have read", and "every suggestion comes from the device or from a source the
/// reader configured, and none is fetched in order to be suggested".
///
/// **That last clause is why this is arithmetic and not a screen.** The suggestions are a
/// projection over publications the app already holds and reading records it already wrote —
/// nothing here takes a connection, a client or a completion handler, which is the same
/// promise ``HomeShelves`` makes and for the same reason. A suggestion that needed a server
/// would be a search page that is blank on a train.
///
/// The proposal is explicit that these three are **a product choice, not a Material or HIG
/// pattern**: Material knows only historical suggestions before typing. So they are specified
/// as behaviour in `navigation-shell` and asserted here, and nothing in the source claims a
/// guideline for them.
@Suite("Search suggestions")
struct SearchScreenTests {

    // MARK: - A library to ask questions of

    private func publication(
        _ title: String,
        series: String? = nil,
        number: String? = nil
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(contentDigest: title),
            format: .cbz,
            displayTitle: title,
            series: series,
            // `number`, not `volume`: `LibraryIndex.issueNumber` reads `number` and nothing
            // else, so a fixture that set only `volume` ordered every issue at
            // `greatestFiniteMagnitude` and *next in series* silently found nothing. A
            // fixture wrong in that direction makes a working rule look broken.
            number: number,
            origin: .inferred
        )
    }

    private func record(
        _ publication: Publication,
        page: Int,
        of total: Int = 40,
        isFinished: Bool = false,
        at moment: Date = Date(timeIntervalSince1970: 1_000)
    ) -> ReadingProgress {
        ReadingProgress(
            identity: publication.identity,
            position: .page(index: page, of: total),
            isFinished: isFinished,
            finishedAt: isFinished ? moment : nil,
            updatedAt: moment
        )
    }

    /// A library with one of each kind, which is the smallest one that can tell the three
    /// sections apart.
    private struct Library {
        let publications: [Publication]
        let progress: [PublicationIdentity: ReadingProgress]

        func record(for publication: Publication) -> ReadingProgress? {
            progress[publication.identity]
        }
    }

    private func mixedLibrary() -> Library {
        // Part-read, so it is what the reader is in the middle of.
        let started = publication("Fine Print")
        // Never opened at all — no record, which is the commonest way to be unread.
        let untouched = publication("Winter Field")
        // A series with volume 1 finished and volume 2 unread: the *next in series* case.
        let volumeOne = publication("Harbour Lights 01", series: "Harbour Lights", number: "1")
        let volumeTwo = publication("Harbour Lights 02", series: "Harbour Lights", number: "2")

        return Library(
            publications: [started, untouched, volumeOne, volumeTwo],
            progress: [
                started.identity: record(started, page: 4),
                volumeOne.identity: record(volumeOne, page: 30, isFinished: true),
            ]
        )
    }

    // MARK: - The three kinds

    @Test("Before a query, the screen offers all three kinds")
    func threeKinds() {
        let library = mixedLibrary()

        let offer = SearchSuggestions.of(
            library.publications,
            progress: library.record(for:)
        )

        #expect(offer.inProgress.map(\.displayTitle) == ["Fine Print"])
        #expect(offer.neverOpened.map(\.displayTitle) == ["Winter Field"])
        #expect(offer.nextInSeries.map(\.displayTitle) == ["Harbour Lights 02"])
        #expect(offer.isEmpty == false)
    }

    @Test("Every suggestion is a publication the library already holds")
    func everySuggestionResolves() {
        let library = mixedLibrary()
        let held = Set(library.publications.map(\.identity))

        let offer = SearchSuggestions.of(
            library.publications,
            progress: library.record(for:)
        )

        // The requirement says every suggestion "comes from the device or from a source the
        // reader configured". A suggestion the model cannot resolve is a row that opens
        // nothing, which is the failure this catches.
        for publication in offer.all {
            #expect(held.contains(publication.identity), "\(publication.displayTitle) is not in the library.")
        }
        #expect(offer.all.count == 3)
    }

    @Test("The three sections never offer the same publication twice")
    func sectionsAreDisjoint() {
        let library = mixedLibrary()

        let offer = SearchSuggestions.of(
            library.publications,
            progress: library.record(for:)
        )

        // Home splits *where you stopped* from *what to start next* deliberately, and one
        // row answering both answers neither — `HomeShelves.upNext` says so at length. The
        // same holds here, and the overlap that would break it is a part-read volume of a
        // started series appearing under both *in progress* and *next in series*.
        let identities = offer.all.map(\.identity)
        #expect(Set(identities).count == identities.count)
    }

    @Test("A part-read volume puts its series out of next-in-series, not into it twice")
    func partReadSeriesIsNotAlsoUpNext() {
        let one = publication("Harbour Lights 01", series: "Harbour Lights", number: "1")
        let two = publication("Harbour Lights 02", series: "Harbour Lights", number: "2")
        let progress: [PublicationIdentity: ReadingProgress] = [
            one.identity: record(one, page: 30, isFinished: true),
            two.identity: record(two, page: 3),
        ]

        let offer = SearchSuggestions.of([one, two]) { progress[$0.identity] }

        #expect(offer.inProgress.map(\.displayTitle) == ["Harbour Lights 02"])
        #expect(offer.nextInSeries.isEmpty)
    }

    // MARK: - Nothing to suggest

    @Test("An empty library offers nothing, and says so rather than drawing headings")
    func emptyLibrary() {
        let offer = SearchSuggestions.of([]) { _ in nil }

        #expect(offer.isEmpty)
        #expect(offer.all.isEmpty)
    }

    @Test("A library read cover to cover still offers nothing, silently")
    func everythingFinished() {
        // `navigation-shell`: "the screen says so in one sentence rather than drawing empty
        // headings". A finished library is the case a reader actually reaches, and the one
        // where three empty headings would look broken rather than complete.
        let done = publication("Fine Print")
        let offer = SearchSuggestions.of([done]) { record($0, page: 40, isFinished: true) }

        #expect(offer.isEmpty)
    }

    @Test("A section with nothing in it is absent rather than present and empty")
    func absentSectionsAreEmpty() {
        // Only unread publications: the screen draws one heading, not three.
        let field = publication("Winter Field")
        let codec = publication("Foreign Codec")

        let offer = SearchSuggestions.of([field, codec]) { _ in nil }

        #expect(offer.inProgress.isEmpty)
        #expect(offer.nextInSeries.isEmpty)
        #expect(offer.neverOpened.count == 2)
        #expect(offer.isEmpty == false)
    }

    // MARK: - Length

    @Test("Each section is bounded, so the screen is a page and not the library")
    func sectionsAreBoundedByLimit() {
        // Search is never exhaustive; the library is, and typing a term is how a reader
        // gets there. An unbounded *never opened* on a library of nine hundred would be the
        // shelf with a different heading.
        let many = (1...40).map { publication("Untouched \($0)") }

        let offer = SearchSuggestions.of(many, limit: 6) { _ in nil }

        #expect(offer.neverOpened.count == 6)
    }
}

/// That the screen is wired to the arithmetic above, and to the shared way in.
///
/// The suite above pins *what the offer is*; it cannot pin *what the screen does with it*,
/// and three of this change's decisions live only at the call site:
///
/// - the at-rest screen replaced the **shelf**, which is what made search read as a filter;
/// - `.searchSuggestions` was dropped, and re-adding it puts the recents back in a dropdown
///   attached to the field while every assertion above stays green;
/// - the empty state offers ``AddSourceMenu``, the same control the library's own empty state
///   offers, rather than a button spelled the same way. `LibraryToolbar` once hand-built a
///   second copy of that menu and left the import out of it.
///
/// **So this reads source text**, for the reason ``CoverRoutingWiringTests`` sets out at
/// length one file away: what is worth pinning is a property of the call site, `swift test`
/// runs on the host with no simulator so these views cannot be composed here, and the only
/// thing that renders them is a UI test on a booted simulator, which no gate runs.
///
/// It is a tripwire, not a proof. `ScreenshotTests.testCaptureSearch` is what shows a reader
/// the screen; delete this the day that run is a gate.
@Suite("Search screen wiring")
struct SearchScreenWiringTests {

    /// The feature's own sources, found from this file rather than from the working directory.
    ///
    /// `#filePath` and not a walk up from the process's directory: this repository nests agent
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs looking for a known
    /// folder climbs out of the checkout under test and validates the parent repository's
    /// copy. That has happened here before.
    private func lines(of name: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath)
        // …/Packages/StoryArcKit/Tests/LibraryFeatureTests/this file → StoryArcKit
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        let path = directory.appendingPathComponent("Sources/LibraryFeature/\(name)").path
        return try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read — has \(name) moved? A guard that cannot find what it guards passes for ever."
        )
    }

    @Test("With nothing typed, the search surface draws the offer and not the shelf")
    func atRestIsNotTheShelf() throws {
        let text = try lines(of: "LibraryView.swift")

        #expect(
            text.contains("SearchAtRest("),
            "The search surface no longer draws SearchAtRest. If it fell back to `inner`, it is the shelf again."
        )
    }

    @Test("The field draws no attached suggestion list")
    func noSearchSuggestions() throws {
        let text = try lines(of: "LibraryView.swift")

        // Only a real modifier, not the comment that explains why it went: the file
        // deliberately names `.searchSuggestions` in prose, and a naive search of the whole
        // text would fail on the explanation while a re-added modifier went unnoticed.
        let modifiers = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(".searchSuggestions") }

        #expect(
            modifiers.isEmpty,
            """
            The field carries a suggestion list again: \(modifiers)
            That draws recents in a dropdown attached to the field. `navigation-shell` asks
            for a screen with headed sections — see SearchAtRest.
            """
        )
    }

    @Test("Nothing to suggest offers the library's own add-a-source menu")
    func emptyStateSharesTheMenu() throws {
        let text = try lines(of: "SearchAtRest.swift")

        #expect(
            text.contains("SearchNothingToSuggest("),
            "SearchAtRest no longer routes an empty offer anywhere. Three empty headings is the failure."
        )
        #expect(
            text.contains("AddSourceMenu("),
            """
            The empty state no longer uses AddSourceMenu.
            `navigation-shell` asks for "the same way of adding a source that the library's
            own empty state offers", and a second menu written here is how one of them ends
            up a row short — which has happened in this file's neighbourhood before.
            """
        )
    }
}
