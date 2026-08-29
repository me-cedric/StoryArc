import Testing

@testable import StoryArcCore

/// How far through a book a position is.
///
/// `ebook-reader` asks for progress as a percentage and forbids presenting a reflowable
/// page number as an identity, so an approximation is allowed and a wrong number is not.
/// Android's `TotalProgressionTest` asserts the same table.
@Suite("Total progression")
struct TotalProgressionTests {

    @Test("A reported zero that the position contradicts is not a report")
    func reportedZeroIsNotAlwaysTrusted() {
        // The defect this exists for: in scroll mode Readium answers 0.0 rather than
        // nothing, so a reader watched "0% read" while scrolling through chapter one.
        let resolved = TotalProgression.resolve(
            reported: 0, within: 0.74, resourceIndex: 0, resourceCount: 2
        )
        #expect(abs(resolved - 0.37) < 0.0001)
    }

    @Test("A reported zero at the very start is trusted, because nothing contradicts it")
    func zeroAtTheStartStaysZero() {
        #expect(
            TotalProgression.resolve(
                reported: 0, within: 0, resourceIndex: 0, resourceCount: 2
            ) == 0
        )
    }

    @Test("A real report wins over the estimate, because the renderer knows more")
    func reportWins() {
        // The renderer has a positions list; the estimate assumes every resource is the
        // same length, which no book is.
        #expect(
            TotalProgression.resolve(
                reported: 0.9, within: 0.1, resourceIndex: 0, resourceCount: 10
            ) == 0.9
        )
    }

    @Test("With no report the estimate stands in, placing the resource then the offset")
    func estimateStandsIn() {
        let resolved = TotalProgression.resolve(
            reported: nil, within: 0.5, resourceIndex: 3, resourceCount: 4
        )
        #expect(abs(resolved - 0.875) < 0.0001)
    }

    @Test("An unknown resource yields zero rather than a guess")
    func unknownResourceIsZero() {
        // A negative index means the href did not match the reading order, and inventing
        // a percentage from that would be worse than admitting to nothing.
        #expect(
            TotalProgression.resolve(
                reported: nil, within: 0.5, resourceIndex: -1, resourceCount: 4
            ) == 0
        )
        #expect(
            TotalProgression.resolve(
                reported: nil, within: 0.5, resourceIndex: 0, resourceCount: 0
            ) == 0
        )
    }

    @Test("Nothing escapes zero to one, whatever the renderer says")
    func staysInRange() {
        #expect(TotalProgression.resolve(reported: 1.4, within: 0, resourceIndex: 0, resourceCount: 1) == 1)
        #expect(TotalProgression.resolve(reported: -0.2, within: 0, resourceIndex: 0, resourceCount: 1) == 0)
        #expect(
            TotalProgression.resolve(
                reported: nil, within: 3, resourceIndex: 1, resourceCount: 2
            ) == 1
        )
    }

    // The defect these pin: on the last page of a two-chapter book the badge read "50%
    // read", and every page of chapter two read the same. Two ways that happens, and both
    // are covered — the resource could not be placed, or it was placed and the fraction
    // through it never arrived.

    @Test("The last page of the last resource is the end of the book")
    func lastPageIsTheEnd() {
        #expect(TotalProgression.resolve(
            reported: nil, within: 1, resourceIndex: 1, resourceCount: 2
        ) == 1)
    }

    @Test("The start of the last resource is half way through a book of two")
    func startOfTheLastResource() {
        #expect(TotalProgression.resolve(
            reported: nil, within: 0, resourceIndex: 1, resourceCount: 2
        ) == 0.5)
    }

    @Test("A locator carrying a fragment still finds its resource")
    func fragmentsDoNotHideAResource() {
        let order = ["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"]

        #expect(TotalProgression.index(of: "OEBPS/ch2.xhtml#fn1", in: order) == 1)
        #expect(TotalProgression.index(of: "OEBPS/ch1.xhtml?highlight=whale", in: order) == 0)
    }

    @Test("A reading order spelled with fragments still matches a plain locator")
    func fragmentsInTheOrderToo() {
        #expect(TotalProgression.index(
            of: "OEBPS/ch2.xhtml", in: ["a.xhtml", "OEBPS/ch2.xhtml#top"]
        ) == 1)
    }

    @Test("A resource that is genuinely not in the reading order is not placed")
    func absentResource() {
        #expect(TotalProgression.index(of: "OEBPS/nav.xhtml", in: ["OEBPS/ch1.xhtml"]) == -1)
    }

    @Test("An unplaceable resource falls back to what the renderer said")
    func fallsBackToTheReport() {
        // Not to zero: the renderer's own answer is the only one left, and a book that
        // jumped to 0% because one href was spelled oddly is worse than an approximation.
        #expect(TotalProgression.resolve(
            reported: 0.42, within: 0.9, resourceIndex: -1, resourceCount: 2
        ) == 0.42)
    }
}
