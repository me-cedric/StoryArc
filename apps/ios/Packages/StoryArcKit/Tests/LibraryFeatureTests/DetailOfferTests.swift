import Testing

@testable import LibraryFeature

/// `publication-detail` 6.6: the page never draws a Read it cannot carry out.
@Suite("The publication page's one offer")
struct DetailOfferTests {
    @Test("Read needs an address, whether or not a copy can be made")
    func readNeedsAnAddress() {
        #expect(DetailOffer.of(isOpenable: true, hasAddress: true, canCopy: false) == .read)
        #expect(DetailOffer.of(isOpenable: true, hasAddress: true, canCopy: true) == .read)
    }

    @Test("With no address, Download is offered when a copy can be made")
    func downloadWithoutAnAddress() {
        #expect(DetailOffer.of(isOpenable: true, hasAddress: false, canCopy: true) == .download)
    }

    @Test("With no address and no copy, nothing is offered")
    func nothingToOffer() {
        #expect(DetailOffer.of(isOpenable: true, hasAddress: false, canCopy: false) == .none)
    }

    @Test("A refused format is offered nothing, whatever else holds")
    func refusedFormat() {
        #expect(DetailOffer.of(isOpenable: false, hasAddress: true, canCopy: true) == .none)
    }
}
