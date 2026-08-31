import Foundation
import Testing

@testable import StoryArcCore

/// `offline-downloads`' *Reading while downloading*, as far as the queue's order can carry
/// it. Android's `DownloadPromotionTest` asserts the same cases.
///
/// The scenario asks for a publication that is still downloading to open immediately and
/// to hand over to the local copy when it lands. The hand-over half already holds — a
/// reader who taps *Read* is given the file the moment it lands, and reading is not
/// interrupted because it has not started. What this fixes is the wait before it: the
/// download a reader is waiting on used to go to the **back** of the queue, so on a metered
/// link, where the concurrency bound is one, they waited out everything they had lined up
/// earlier and were not reading.
///
/// What is still missing is streaming itself, and it is missing outside this file: no
/// `RandomAccessSource` over HTTP range requests is registered, so a publication that is
/// still arriving cannot be read from the server while it arrives.
@Suite("A download a reader is waiting on goes to the head of the queue")
struct DownloadPromotionTests {
    private func download(_ id: String, state: Download.State = .queued) -> Download {
        Download(
            id: id,
            title: id,
            remote: URL(filePath: "/nowhere/\(id).cbz"),
            mediaType: "application/vnd.comicbook+zip",
            state: state
        )
    }

    private func ids(_ library: DownloadLibrary) -> [String] {
        library.downloads.map(\.id)
    }

    @Test("The waited-on download moves ahead of what was queued before it")
    func itMovesToTheHead() {
        let library = DownloadLibrary(downloads: [
            download("big"), download("other"), download("wanted"),
        ])

        #expect(ids(library.promoting("wanted")) == ["wanted", "big", "other"])
    }

    @Test("A running download keeps its slot")
    func runningIsNotPreempted() {
        // Nothing is cancelled and nothing is preempted: this is the reorder the spec
        // already grants the reader, not a priority scheme.
        let library = DownloadLibrary(downloads: [
            download("running", state: .running), download("big"), download("wanted"),
        ])

        #expect(ids(library.promoting("wanted")) == ["running", "wanted", "big"])
    }

    @Test("A download already at the head is left where it is")
    func headStaysPut() {
        let library = DownloadLibrary(downloads: [download("wanted"), download("big")])

        #expect(library.promoting("wanted") == library)
    }

    @Test("Only a queued download can be promoted")
    func onlyTheQueued() {
        let library = DownloadLibrary(downloads: [
            download("big"),
            download("running", state: .running),
            download("done", state: .finished),
            download("held", state: .paused(.byReader)),
        ])

        #expect(library.promoting("running") == library)
        #expect(library.promoting("done") == library)
        #expect(library.promoting("held") == library)
        #expect(library.promoting("absent") == library)
    }

    @Test("Everything else keeps its order")
    func theRestIsUndisturbed() {
        let library = DownloadLibrary(downloads: [
            download("done", state: .finished),
            download("one"), download("two"), download("three"), download("wanted"),
        ])

        #expect(ids(library.promoting("wanted")) == ["done", "wanted", "one", "two", "three"])
    }
}
