import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// Which question a reader is being asked when they press *Stop* or *Remove*.
///
/// The Downloads destination asked one question for two acts. *Stop* on a row that was
/// still arriving put up *Remove this download?* — "This deletes the copy of Harbour
/// Lights 03 on this device. Your reading position is kept, and it can be downloaded
/// again." — over a transfer with no copy on the device and no reading position to keep
/// (`ios-downloads-stop-confirm.png`). One string doing two jobs, and both sentences of it
/// false in the case the sweep photographed.
///
/// Android's `DownloadQueueRemovalTest` is this suite, case for case.
@Suite("Download removal confirmations")
struct DownloadQueueRemovalTests {

    /// The reason the September sweep's injected record carries, three attempts in.
    private static let failed = Download.State.failed(
        reason: "The server did not answer in time.",
        attempts: 3
    )

    private func download(
        state: Download.State,
        sourceID: UUID? = UUID(uuidString: "0f2b6a1e-1111-4111-8111-111111111111")
    ) -> Download {
        Download(
            id: "one",
            sourceID: sourceID,
            title: "Harbour Lights 03",
            remote: URL(string: "https://example.invalid/hl03.epub")!,
            mediaType: "application/epub+zip",
            state: state,
            expectedBytes: 8_400_000,
            downloadedBytes: 3_100_000
        )
    }

    /// The defect, stated as a test: a transfer under way is stopped, not removed.
    ///
    /// Paused is here on purpose, all three ways. The row of a paused download still offers
    /// *Stop*, because a retry from the Downloads screen would re-queue it only to have it
    /// pause again for the same Wi-Fi or the same missing room — so its confirmation is the
    /// transfer's, not the discard's.
    @Test(
        "A transfer that has not landed is a stop",
        arguments: [
            Download.State.queued,
            .running,
            .paused(.byReader),
            .paused(.waitingForWiFi),
            .paused(.outOfSpace),
        ]
    )
    func inFlight(state: Download.State) {
        #expect(DownloadQueueRemoval.confirmation(for: download(state: state)) == .stopping)
    }

    /// And one that stopped by itself is neither.
    ///
    /// "This stops the transfer" is as untrue of a failed download as the removal sentence
    /// is of a running one — the transfer stopped three attempts ago. The row offers *Remove*
    /// here rather than *Stop*, so the question has to be a removal that promises nothing
    /// about a copy.
    @Test("A failed transfer is discarded, not stopped")
    func failed() {
        #expect(DownloadQueueRemoval.confirmation(for: download(state: Self.failed)) == .discarding)
    }

    /// A finished download is the case the old string was actually written for.
    @Test("A finished download is a removal")
    func finished() {
        #expect(DownloadQueueRemoval.confirmation(for: download(state: .finished)) == .removing)
    }

    /// And an import is the third case, which `local-library` asks for more words than
    /// either of the other two.
    @Test("A finished import names the original it is not touching")
    func imported() {
        let copy = download(state: .finished, sourceID: ImportedCopies.sourceID)
        #expect(DownloadQueueRemoval.confirmation(for: copy) == .removingImport)
    }

    /// **The ordering, which is the whole reason this is a type and not an `if` in a view.**
    /// An import is written into the record as `queued` and marked finished a line later, so
    /// a record caught between the two — a crash mid-import, a build that saved before it
    /// marked — is an import that has not landed. Nothing about it is on the device to free,
    /// so it is a stop, and the import sentence promising to free a size would be naming a
    /// size the reader would not get back.
    @Test("An import that has not landed is still a stop")
    func importInFlight() {
        let copy = download(state: .queued, sourceID: ImportedCopies.sourceID)
        #expect(DownloadQueueRemoval.confirmation(for: copy) == .stopping)
    }

    /// **The second half of the ordering: failed is asked before where it came from.** A
    /// record that carries the import source and a failure is an import that never landed,
    /// and the only sentence true of it is the discard's. Ask *imported?* first and it is
    /// offered the import removal — a promise to free a size the reader never had, which is
    /// the exact sentence the first half of the ordering exists to keep from a queued import.
    /// This is the case that fails when the two questions are swapped.
    @Test("A failed import is discarded, not an import removal")
    func failedImport() {
        let copy = download(state: Self.failed, sourceID: ImportedCopies.sourceID)
        #expect(DownloadQueueRemoval.confirmation(for: copy) == .discarding)
    }
}
