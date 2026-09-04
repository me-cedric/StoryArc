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
@Suite("Download removal confirmations")
struct DownloadQueueRemovalTests {

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
    @Test(
        "A transfer that has not landed is a stop",
        arguments: [
            Download.State.queued,
            .running,
            .paused(.byReader),
            .paused(.waitingForWiFi),
            .failed(reason: "The server did not answer in time.", attempts: 3),
        ]
    )
    func inFlight(state: Download.State) {
        #expect(DownloadQueueRemoval.confirmation(for: download(state: state)) == .stopping)
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
}
