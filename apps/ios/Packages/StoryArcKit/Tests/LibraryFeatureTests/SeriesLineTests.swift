import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What the second line under a cover is allowed to say.
///
/// `library-browsing` wants the caption to distinguish a publication from its neighbours,
/// and a line that repeats the title distinguishes nothing — it reads as a rendering fault.
/// The shelf did exactly that on every numbered series: the guard compared the *bare*
/// series against the title while the string it returned was the *composed*
/// `"<series> #<number>"`, so `Ashfall` + `1` under the title `Ashfall #1` sailed through.
/// Six covers on one iPhone screen said `Ashfall #1` twice.
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
}
