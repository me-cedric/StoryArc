import Foundation
import Testing

@testable import StoryArcCore

/// A series line says something the title does not, or it is not drawn.
///
/// **Photographed on 2026-09-05**, on Android: the publication page for `Broken Transfer.cbz`
/// read `Broken Transfer` in the app bar and `Broken Transfer` again immediately beneath it.
/// A title inferred from a filename is usually the series and the number joined back together,
/// so a standalone publication carries a series equal to its own title.
///
/// iOS's page was already guarded — `DetailHero` has called ``seriesLine(for:)`` since it was
/// written — but **the search row was not**: ``SearchResult/init(_:kind:)`` took
/// `publication.series ?? publication.authors.first` with nothing compared to anything, so the
/// same standalone answered a search with its own title printed twice, and fell through to
/// neither the series nor the author. That is the iOS twin of the Android defect, and these
/// cases pin the rule the row now goes through.
///
/// The cases below are Android's `SeriesLineTest` case for case, deliberately: the two
/// platforms answer this identically or the same book reads differently on each. The overloads
/// over `Publication` and `OpdsEntry` stay in `LibraryFeature` and have their own suite.
@Suite("Series line")
struct SeriesLineTests {

    @Test("A series that repeats the title is not drawn")
    func repetitionIsRefused() {
        #expect(seriesLine(series: "Broken Transfer", title: "Broken Transfer") == nil)
    }

    @Test("Case alone is not a second fact about the publication")
    func caseIsNotAFact() {
        #expect(seriesLine(series: "broken transfer", title: "Broken Transfer") == nil)
    }

    @Test("A series that says something else is drawn")
    func aDifferentSeriesIsDrawn() {
        #expect(seriesLine(series: "Harbour Lights", title: "The Ridge Road") == "Harbour Lights")
    }

    @Test("The number joins the series, and the pair is compared to the title")
    func theComposedLineIsWhatIsCompared() {
        // The case that matters for a feed generated from filenames: the entry's title already
        // reads `Harbour Lights #1`, so the line built from its parts must not be drawn again.
        #expect(seriesLine(series: "Harbour Lights", number: "1", title: "Harbour Lights #1") == nil)
        #expect(
            seriesLine(series: "Harbour Lights", number: "2", title: "Harbour Lights #1")
                == "Harbour Lights #2"
        )
    }

    @Test("No series, or a blank one, draws nothing")
    func anAbsentSeriesDrawsNothing() {
        #expect(seriesLine(series: nil, title: "Anything") == nil)
        // `<Series></Series>` indented onto its own line is the ordinary shape of "no series".
        // iOS tested `isEmpty` here until 2026-09-05 and drew a line of spaces where Android
        // drew nothing.
        #expect(seriesLine(series: "   ", title: "Anything") == nil)
    }

    @Test("A blank number is not joined")
    func aBlankNumberIsNotJoined() {
        #expect(seriesLine(series: "Harbour Lights", number: " ", title: "Other") == "Harbour Lights")
    }
}

/// What a search row says under a title it found.
///
/// `library-browsing` wants the second line to tell a reader which "Volume 1" they are looking
/// at. A line repeating the title tells them nothing, and it costs them the author as well —
/// the `??` fallback never runs when the series is present but useless.
@Suite("Search row detail line")
struct SearchResultDetailTests {

    private func publication(
        title: String,
        series: String? = nil,
        authors: [String] = []
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/\(title).cbz"),
            format: .cbz,
            displayTitle: title,
            series: series,
            authors: authors,
            origin: .inferred
        )
    }

    @Test("A standalone does not answer a search with its own title twice")
    func aStandaloneDoesNotRepeatItself() {
        let row = SearchResult(
            publication(title: "Broken Transfer", series: "Broken Transfer", authors: ["Ada Vance"]),
            kind: .publication
        )
        #expect(row.title == "Broken Transfer")
        // The author, because the series had nothing to add — not the series, and not nothing.
        #expect(row.detail == "Ada Vance")
    }

    @Test("A series that distinguishes the row is still the row's detail line")
    func aRealSeriesWins() {
        let row = SearchResult(
            publication(title: "The Ridge Road", series: "Harbour Lights", authors: ["Ada Vance"]),
            kind: .publication
        )
        #expect(row.detail == "Harbour Lights")
    }

    @Test("With no series and no author there is no second line at all")
    func nothingToSayIsSaidAsNothing() {
        let row = SearchResult(publication(title: "Glasshouse"), kind: .publication)
        #expect(row.detail == nil)
    }
}
