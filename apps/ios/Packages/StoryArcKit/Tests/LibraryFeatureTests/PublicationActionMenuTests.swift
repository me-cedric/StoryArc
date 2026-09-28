import Testing

@testable import LibraryFeature
import StoryArcCore

/// The one action list a publication offers, wherever it is drawn — the two pieces this menu
/// decides for itself rather than borrowing from `AddToShelfMenu`: whether there is anything
/// to download or to remove, and — through `DetailActions.canCopy`, which now asks the same
/// question — whether the publication's page offers to copy it.
struct PublicationActionMenuTests {

    private func publication(
        format: PublicationFormat = .cbz,
        streaming: StreamingCapability = .streams
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/one.\(format.rawValue)"),
            format: format,
            displayTitle: "One",
            origin: .inferred,
            streaming: streaming
        )
    }

    @Test("A publication no decoder will open cannot be downloaded")
    func refusedPublicationCannotBeDownloaded() {
        let refused = publication(format: .cb7, streaming: .refused)
        #expect(!refused.isOpenable)
        #expect(!PublicationActions.canDownload(refused))
    }

    @Test("A folder of images has nothing a single file could copy")
    func imageFolderCannotBeDownloaded() {
        #expect(!PublicationActions.canDownload(publication(format: .imageFolder)))
    }

    @Test("An ordinary openable publication can be downloaded")
    func ordinaryPublicationCanBeDownloaded() {
        #expect(PublicationActions.canDownload(publication(format: .cbz)))
    }

    @Test("A kept copy offers to remove itself, whatever else is true of it")
    func keptCopyOffersRemoval() {
        #expect(DownloadOffer.of(publication(format: .imageFolder), isKept: true, isLocalFile: true) == .remove)
        let refused = publication(format: .cb7, streaming: .refused)
        #expect(DownloadOffer.of(refused, isKept: true, isLocalFile: false) == .remove)
    }

    @Test("A copy that could be fetched and is not kept offers to download")
    func fetchableCopyOffersDownload() {
        #expect(DownloadOffer.of(publication(format: .cbz), isKept: false, isLocalFile: true) == .download)
    }

    @Test("Nothing that could be fetched offers neither")
    func nothingFetchableOffersNeither() {
        #expect(DownloadOffer.of(publication(format: .imageFolder), isKept: false, isLocalFile: true) == .none)
        let refused = publication(format: .cb7, streaming: .refused)
        #expect(DownloadOffer.of(refused, isKept: false, isLocalFile: true) == .none)
    }

    @Test("A row whose bytes are on a server offers no download the menu cannot deliver")
    func serverRowOffersNoDownload() {
        // The menu copies a file that is already on this device. A Kavita, OPDS or share
        // row has no such file, so a Download button there would change nothing.
        #expect(DownloadOffer.of(publication(format: .cbz), isKept: false, isLocalFile: false) == .none)
    }
}
