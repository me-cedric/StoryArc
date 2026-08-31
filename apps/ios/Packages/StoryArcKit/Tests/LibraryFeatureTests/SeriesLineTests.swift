import Catalogue
import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What the second line under a title is allowed to say, on every surface that draws one.
///
/// `library-browsing` wants the caption to distinguish a publication from its neighbours,
/// and a line that repeats the title distinguishes nothing — it reads as a rendering fault.
/// The shelf did exactly that on every numbered series: the guard compared the *bare*
/// series against the title while the string it returned was the *composed*
/// `"<series> #<number>"`, so `Ashfall` + `1` under the title `Ashfall #1` sailed through.
/// Six covers on one iPhone screen said `Ashfall #1` twice.
///
/// The rule is now one function over three types' worth of call sites — the shelf, the
/// list, the publication's own page and both catalogue surfaces — so the cases below are
/// asserted once and every caller inherits them.
@Suite("Series line")
struct SeriesLineTests {

    private func publication(
        title: String,
        series: String? = nil,
        number: String? = nil,
        authors: [String] = []
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/\(title).cbz"),
            format: .cbz,
            displayTitle: title,
            series: series,
            number: number,
            authors: authors,
            origin: .inferred
        )
    }

    @Test("A composed line identical to the title is not shown")
    func composedRepetitionIsRefused() {
        let one = publication(title: "Ashfall #1", series: "Ashfall", number: "1")
        #expect(seriesLine(for: one) == nil)
    }

    @Test("A composed line that adds the number is shown")
    func composedLineThatAddsSomethingIsKept() {
        // The title is the series alone, so the number is a fact the title does not carry.
        let one = publication(title: "Ashfall", series: "Ashfall", number: "1")
        #expect(seriesLine(for: one) == "Ashfall #1")
    }

    @Test("A series that is not the title is shown, numbered or not")
    func aDistinctSeriesIsKept() {
        #expect(seriesLine(for: publication(title: "Cinders", series: "Ashfall")) == "Ashfall")
        #expect(
            seriesLine(for: publication(title: "Cinders", series: "Ashfall", number: "3"))
                == "Ashfall #3"
        )
    }

    @Test("A bare series equal to the title is not shown")
    func bareRepetitionIsRefused() {
        #expect(seriesLine(for: publication(title: "Ashfall", series: "Ashfall")) == nil)
    }

    @Test("Case is not a second fact")
    func caseAloneIsNotADifference() {
        // A title inferred from a filename is often the series and the number joined back
        // together, and `ASHFALL #1` over `Ashfall #1` is the same words in a hat.
        let one = publication(title: "ASHFALL #1", series: "Ashfall", number: "1")
        #expect(seriesLine(for: one) == nil)
    }

    @Test("A publication with no series has no line")
    func noSeriesNoLine() {
        #expect(seriesLine(for: publication(title: "Glasshouse")) == nil)
    }

    /// The other half of the fix: what the cover says *instead*. A caption that fell back to
    /// nothing would trade a repeated line for a missing one.
    @Test("The cover falls through to the author when the series line is refused")
    @MainActor
    func theCoverFallsThroughToTheAuthor() {
        let repeated = publication(
            title: "Ashfall #1",
            series: "Ashfall",
            number: "1",
            authors: ["Ada Lovelace"]
        )
        let distinct = publication(
            title: "Cinders",
            series: "Ashfall",
            number: "3",
            authors: ["Ada Lovelace"]
        )

        #expect(cell(repeated).subtitle == "Ada Lovelace")
        #expect(cell(distinct).subtitle == "Ashfall #3")
    }

    @MainActor
    private func cell(_ publication: Publication) -> CoverCell {
        CoverCell(
            publication: publication,
            model: LibraryModel(),
            onOpen: { _ in },
            maxPixelSize: 200
        )
    }

    // MARK: - A catalogue entry, which is not a publication

    private func entry(
        title: String,
        series: String? = nil,
        index: Double? = nil
    ) -> OpdsEntry {
        OpdsEntry(id: "urn:\(title)", title: title, series: series, seriesIndex: index)
    }

    /// The catalogue's defect was worse than the shelf's: it composed the line and compared
    /// nothing at all, so this duplicated unconditionally on every feed whose titles carry
    /// their own numbers — which is most feeds generated from filenames.
    @Test("A catalogue entry does not repeat its own title")
    func aCatalogueEntryDoesNotRepeatItself() {
        #expect(seriesLine(for: entry(title: "Harbour Lights #1", series: "Harbour Lights", index: 1)) == nil)
        #expect(seriesLine(for: entry(title: "HARBOUR LIGHTS #1", series: "Harbour Lights", index: 1)) == nil)
        #expect(seriesLine(for: entry(title: "Harbour Lights", series: "Harbour Lights")) == nil)
    }

    @Test("A catalogue entry keeps a line that adds something")
    func aCatalogueEntryKeepsWhatItAdds() {
        #expect(
            seriesLine(for: entry(title: "Harbour Lights", series: "Harbour Lights", index: 1))
                == "Harbour Lights #1"
        )
        #expect(seriesLine(for: entry(title: "Low Tide", series: "Harbour Lights")) == "Harbour Lights")
        #expect(
            seriesLine(for: entry(title: "Low Tide", series: "Harbour Lights", index: 12))
                == "Harbour Lights #12"
        )
    }

    @Test("A catalogue entry with no series has no line")
    func aCatalogueEntryWithNoSeriesHasNoLine() {
        #expect(seriesLine(for: entry(title: "Low Tide")) == nil)
        // A feed that declares an empty series has declared nothing. The publication side
        // never sees one, because the scan does not produce it; a server can send anything.
        #expect(seriesLine(for: entry(title: "Low Tide", series: "")) == nil)
    }

    /// OPDS states the index as a number, and a number a server sends is a number this app
    /// did not choose. `Int(Double.nan)` is a trap, not a caption, so it is refused: the
    /// series still shows, without an index it cannot write down.
    @Test("An index that is not a finite number is dropped, not converted")
    func anUnwritableIndexIsDropped() {
        #expect(seriesLine(for: entry(title: "Low Tide", series: "Harbour Lights", index: .nan)) == "Harbour Lights")
        #expect(
            seriesLine(for: entry(title: "Low Tide", series: "Harbour Lights", index: .infinity))
                == "Harbour Lights"
        )
    }
}
