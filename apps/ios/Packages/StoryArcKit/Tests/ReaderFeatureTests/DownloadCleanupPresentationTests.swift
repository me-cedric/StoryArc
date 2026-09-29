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

    @Test("A download that stays gets the offer to remove it")
    func staysOffersRemoval() {
        let offer = DownloadCleanupOffer(isRemovedOnClose: { false }, onRemove: {}, onKeep: {})
        #expect(DownloadCleanupPresentation.resolved(for: offer) == .offerRemoval)
    }

    @Test("A download that goes on close says so, and offers to keep it")
    func goesStatesAndOffersKeep() {
        let offer = DownloadCleanupOffer(isRemovedOnClose: { true }, onRemove: {}, onKeep: {})
        #expect(DownloadCleanupPresentation.resolved(for: offer) == .stateAndOfferKeep)
    }

    @Test("After Keep, the screen stops saying the download goes")
    func keepChangesTheScreen() {
        // Before, the sentence and the Keep button stayed up after the tap, and the
        // sentence was then false.
        let offer = DownloadCleanupOffer(isRemovedOnClose: { true }, onRemove: {}, onKeep: {})
        #expect(DownloadCleanupPresentation.resolved(for: offer, choice: false) == .offerRemoval)
    }

    @Test("After Remove download, the screen says it goes on close, and offers Keep")
    func removeChangesTheScreen() {
        let offer = DownloadCleanupOffer(isRemovedOnClose: { false }, onRemove: {}, onKeep: {})
        #expect(DownloadCleanupPresentation.resolved(for: offer, choice: true) == .stateAndOfferKeep)
    }
}
