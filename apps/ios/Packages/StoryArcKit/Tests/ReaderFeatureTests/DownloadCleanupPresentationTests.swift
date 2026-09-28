import Testing

@testable import ReaderFeature

/// What the end screen shows about a publication's download (D7). Android's
/// `DownloadCleanupPresentationTest` asserts the same table.
@Suite("Download cleanup presentation")
struct DownloadCleanupPresentationTests {

    @Test("No offer at all is nothing shown — most publications were never a download")
    func noOfferIsNothing() {
        #expect(DownloadCleanupPresentation.resolved(for: nil) == .none)
    }

    @Test("With the sweep off, the end screen offers to remove the download")
    func sweepOffOffersRemoval() {
        let offer = DownloadCleanupOffer(automaticCleanupIsOn: false, onRemove: {}, onKeep: {})
        #expect(DownloadCleanupPresentation.resolved(for: offer) == .offerRemoval)
    }

    @Test("With the sweep on, the end screen states it and offers to keep this one")
    func sweepOnStatesAndOffersKeep() {
        let offer = DownloadCleanupOffer(automaticCleanupIsOn: true, onRemove: {}, onKeep: {})
        #expect(DownloadCleanupPresentation.resolved(for: offer) == .stateAndOfferKeep)
    }
}
