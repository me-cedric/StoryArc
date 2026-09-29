import Foundation
import StoryArcCore
import Testing

@testable import Persistence

/// The page number a recorded position reports to Kavita.
///
/// The field report: an EPUB read from Kavita never pushed its position -- `reportToKavita`
/// recognised only `.page`, so a reflowable position was dropped silently on every close.
/// Android's `PageToReportTest` asserts the same cases.
@Suite("The page a Kavita report sends")
struct KavitaOriginPageToReportTests {

    private func origin(pages: Int) -> KavitaOrigin {
        KavitaOrigin(sourceId: UUID().uuidString, libraryId: 1, seriesId: 7, volumeId: 3, chapterId: 42, pages: pages)
    }

    @Test("A paged position reports its own index, ignoring the chapter's page count")
    func pagedPositionReportsItsIndex() {
        #expect(origin(pages: 0).pageToReport(.page(index: 3, of: 10)) == 3)
    }

    @Test("A reflowable position becomes a page, from the chapter's own length")
    func reflowablePositionBecomesAPage() {
        // Halfway through a 21-page chapter is page 10 (zero-based), the same arithmetic
        // `KavitaExchange.pageNumber` is already asserted against.
        #expect(origin(pages: 21).pageToReport(.reflowable(progression: 0.5, locator: "{}")) == 10)
    }

    @Test("A reflowable position with no known page count is not reported")
    func reflowableWithNoPageCountIsNotReported() {
        #expect(origin(pages: 0).pageToReport(.reflowable(progression: 0.5, locator: "{}")) == nil)
    }

    @Test("A listening position takes the same rule as a reflowable one")
    func listeningPositionBecomesAPage() {
        // Part 1 of 2, at the start of it: a fraction of 0.5, the same as the reflowable
        // case above.
        #expect(
            origin(pages: 21).pageToReport(.listening(part: 1, partCount: 2, offset: 0, of: nil))
                == 10
        )
    }
}
