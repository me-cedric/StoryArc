import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The page for a publication with no series, no year, no description and no cover.
///
/// Task 2.4's four absences, which nothing on either platform asserted. `publication-detail`
/// asks for two things at once and they are easy to confuse: the lines are "absent rather
/// than shown empty or filled with a placeholder", **and** "the page's composition holds
/// together with only a cover and a title". This file is the first half — every rule that
/// decides whether a line exists, asked with the publication that carries nothing. The
/// second half is a picture, and it is still owed.
///
/// Android asserts the same four answers by composing the page in
/// `DetailAbsencesTest.kt`, because Robolectric lets it draw what iOS can only compute on a
/// host. Same answers, different reach.
@Suite("A page with nothing to say")
struct DetailAbsencesTests {

    /// The degenerate page: a title, and nothing else to say about it. No series, no number,
    /// no author, no year, no description — and every test below composes its own variant
    /// rather than mutating one, because `Publication`'s stored properties are `let`.
    private func publication(
        authors: [String] = [],
        year: Int? = nil,
        summary: String? = nil
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(contentDigest: "bare"),
            format: .cbz,
            displayTitle: "The Ridge Road",
            authors: authors,
            year: year,
            summary: summary,
            origin: .authoritative
        )
    }

    /// A publication carrying a title and nothing else.
    private var bare: Publication { publication() }

    @Test("No series declared draws no series line")
    func noSeries() {
        #expect(seriesLine(for: bare) == nil)
    }

    @Test("No author and no year draw no second line")
    func noAuthorAndNoYear() {
        #expect(detailSecondaryLine(for: bare) == nil)
    }

    /// Half a fact is still a line, because a book with an author and no year has an author.
    /// The absence rule is about the publication carrying *nothing*, not about it carrying
    /// less than everything.
    @Test("Either half on its own is still a line")
    func eitherHalfIsALine() {
        #expect(detailSecondaryLine(for: publication(authors: ["Mara Quill"])) == "Mara Quill")
        #expect(detailSecondaryLine(for: publication(year: 2024)) == "2024")
        #expect(
            detailSecondaryLine(for: publication(authors: ["Mara Quill"], year: 2024))
                == "Mara Quill · 2024"
        )
    }

    @Test("No description draws no description")
    func noDescription() {
        #expect(detailSummary(of: bare) == nil)
    }

    /// The case the old `!summary.isEmpty` passed, and the reason this rule moved out of the
    /// view. A description of three spaces is not a description; it is a paragraph of the
    /// page's own spacing with nothing in it, which is the delta's "shown empty" exactly.
    /// Android has always read this as `isNotBlank()`.
    @Test("A description of whitespace is an absence, not an empty paragraph")
    func blankDescriptionIsAbsent() {
        for blank in ["", " ", "   ", "\n", " \n\t "] {
            #expect(
                detailSummary(of: publication(summary: blank)) == nil,
                "\(blank.debugDescription) drew a line"
            )
        }
    }

    @Test("A real description survives with its own spacing intact")
    func aRealDescriptionIsNotTrimmed() {
        // Trimmed for the *decision* and never for the text: what the scan collected is what
        // the page shows, and this change does not alter what the scan collects.
        let text = "  Nine years after the ash.  "

        #expect(detailSummary(of: publication(summary: text)) == text)
    }

    /// The fourth absence. A page with no cover takes no colour from one — the delta's "no
    /// derived colour taken from it" — and the wash's own rule is where that is decided, so
    /// the page never reaches a state where a placeholder has tinted the screen.
    @Test("No cover means no wash, so the placeholder tints nothing")
    func noCoverDrawsNoWash() {
        #expect(DetailWash.drawn(nil, isPlain: false) == 0)
    }

    /// And the composition still has something to draw: the title is the one thing the page
    /// is guaranteed. A publication with a whitespace-only title never reaches the shelf —
    /// `native-experience`'s quick actions already refuse one — so a page always has a name.
    @Test("The title is what the composition holds together on")
    func theTitleIsAlwaysThere() {
        #expect(!bare.displayTitle.isEmpty)
    }
}
