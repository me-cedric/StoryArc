import Testing

@testable import EpubReaderFeature

/// Whether a page on screen is the end of the book.
///
/// The field report: an EPUB never finished on its own, because Readium's own locator
/// reports the *lower* bound of what is visible. On the last page of a short resource, a
/// reader could see the last line of the book and the app would still say `total < 0.999`.
/// `EpubReaderModel.isAtEnd` is the rule `record(_:)` uses instead, lifted out so a test can
/// reach it without a navigator.
@Suite("An EPUB page is the end of the book")
struct EpubFinishedAtEndTests {

    @Test("A viewport reaching the end finishes the book, even if the locator's own total does not")
    func viewportUpperBoundWins() {
        #expect(EpubReaderModel.isAtEnd(total: 0.96, viewportUpperBound: 1.0))
        #expect(!EpubReaderModel.isAtEnd(total: 0.96, viewportUpperBound: 0.98))
    }

    @Test("With no viewport reported yet, the locator's own total decides")
    func fallsBackToTheLocatorsTotal() {
        #expect(EpubReaderModel.isAtEnd(total: 0.9995, viewportUpperBound: nil))
        #expect(!EpubReaderModel.isAtEnd(total: 0.96, viewportUpperBound: nil))
    }
}
