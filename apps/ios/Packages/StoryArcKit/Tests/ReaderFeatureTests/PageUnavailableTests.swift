import Testing

@testable import ReaderFeature

/// `close-the-audited-gaps` 23.5: a page whose read is still under way is loading, never
/// unreadable. A 2.6 GB PDF kept PDFKit mapping for seconds, and the reader drew "This page
/// could not be read" for all of them before drawing page 1.
@MainActor
@Suite("Whether a page is drawn as a problem")
struct PageUnavailableTests {
    @Test("A page whose read is under way is not a problem, however long it takes")
    func readingIsLoading() {
        #expect(!ReaderModel.isUnavailable(attempted: true, isReading: true, isDecoded: false))
    }

    @Test("A page whose read ended with no image is a problem")
    func endedWithNothingIsAProblem() {
        #expect(ReaderModel.isUnavailable(attempted: true, isReading: false, isDecoded: false))
    }

    @Test("A page that decoded is not a problem")
    func decodedIsFine() {
        #expect(!ReaderModel.isUnavailable(attempted: true, isReading: false, isDecoded: true))
    }

    @Test("A page nobody has asked for yet is not a problem")
    func notAskedYet() {
        #expect(!ReaderModel.isUnavailable(attempted: false, isReading: false, isDecoded: false))
    }
}
