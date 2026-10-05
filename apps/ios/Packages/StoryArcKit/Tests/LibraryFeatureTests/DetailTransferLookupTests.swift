import Foundation
import Testing

import StoryArcCore

@testable import LibraryFeature

/// Which record the publication page watches while a catalogue book arrives.
///
/// `offline-downloads`' *The iOS publication page never finds, starts or shows an OPDS
/// download*. The page asked the download store for the library row's own id, and dl-core 1.2
/// records an OPDS download under a source-scoped key instead — so the page found no record
/// for any catalogue publication, had no address to stream from and drew no progress. These
/// assert the key the page asks for, and that it is the same key the queue writes.
@Suite("The publication page's transfer")
struct DetailTransferLookupTests {
    private let source = UUID()

    /// A catalogue row exactly as ``OpdsContributor`` builds one: keyed on the source and the
    /// entry, with no file of its own.
    private func catalogueRow(entry: String = "hl09") -> Publication {
        Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: source, remoteID: "opds:\(entry)")
            ),
            format: .cbz,
            displayTitle: "Harbour Lights 09",
            origin: .authoritative,
            sourceID: source
        )
    }

    private func transfer(id: String, downloaded: Int64 = 400, expected: Int64? = 1_000) -> Download {
        Download(
            id: id,
            sourceID: source,
            title: "Harbour Lights 09",
            remote: URL(string: "https://library.example/hl09.cbz") ?? URL(fileURLWithPath: "/"),
            mediaType: "application/vnd.comicbook+zip",
            state: .running,
            expectedBytes: expected,
            downloadedBytes: downloaded
        )
    }

    @Test("A catalogue row names the source-scoped key the queue writes, not the row's own id")
    func catalogueRowNamesTheQueuesKey() {
        let row = catalogueRow()

        #expect(RemoteMemberResolution.downloadID(of: row) == "opds:\(source.uuidString):hl09")
        #expect(
            RemoteMemberResolution.downloadID(of: row) != row.id,
            "The row's own id is `srv:<source>:opds:<entry>`, which is what the page used to ask for."
        )
    }

    @Test("The record the queue wrote is the record the page finds")
    func theQueuesRecordIsFound() throws {
        let row = catalogueRow()
        let library = DownloadLibrary(downloads: [transfer(id: "opds:\(source.uuidString):hl09")])

        let found = try #require(RemoteMemberResolution.record(of: row, in: library))

        #expect(found.fraction == 0.4)
    }

    @Test("A library with only the catalogue row's own id as a key finds nothing")
    func theRowsOwnKeyIsNotTheQueues() {
        let row = catalogueRow()
        let library = DownloadLibrary(downloads: [transfer(id: "opds:\(UUID().uuidString):hl09")])

        #expect(
            RemoteMemberResolution.record(of: row, in: library) == nil,
            "Another catalogue's entry of the same name was taken for this one."
        )
    }

    @Test("A publication that is not a catalogue row keeps its own id")
    func aLocalRowKeepsItsOwnID() throws {
        let local = Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/tidal-reach.cbz"),
            format: .cbz,
            displayTitle: "Tidal Reach",
            origin: .authoritative
        )
        let library = DownloadLibrary(downloads: [transfer(id: local.id)])

        #expect(RemoteMemberResolution.downloadID(of: local) == local.id)
        let found = try #require(RemoteMemberResolution.record(of: local, in: library))
        #expect(found.id == local.id)
    }

    @Test("The page and the queue spell the key the same way")
    @MainActor
    func thePageAndTheQueueAgree() {
        let queue = DownloadQueue(sourceID: source, settings: { AppSettings() })

        #expect(
            queue.downloadID(for: "hl09") == RemoteMemberResolution.downloadID(of: catalogueRow()),
            "A download the catalogue page queued is not the one the publication page watches."
        )
    }

    /// The wiring, read as text for the reason ``PublicationPaneTests`` sets out: `swift test`
    /// runs on the host with no window, so no assertion in this process can watch the page
    /// draw. A tripwire, not a proof — the proof is a frame from a booted simulator.
    @Test("The page watches the one app-level queue rather than a snapshot of the store")
    func thePageWatchesTheQueue() {
        let page = LibraryFeatureSource.code(of: "Sources/LibraryFeature/PublicationDetailView.swift")

        #expect(page.contains("DownloadQueue.shared()"))
        #expect(page.contains("RemoteMemberResolution.record(of: publication, in: queue.library)"))
        #expect(
            !page.contains("DownloadStore().library()[publication.id]"),
            "The page is back to the one-shot store read that found no OPDS record."
        )
    }

    @Test("The actions draw the transfer's own state and its progress")
    func theActionsDrawTheTransfer() {
        let actions = LibraryFeatureSource.code(of: "Sources/LibraryFeature/DetailActions.swift")

        #expect(actions.contains("DetailTransferLine(transfer: transfer"))
        #expect(actions.contains("ProgressView(value: fraction)"))
        #expect(actions.contains("case let .failed(reason, _):"))
    }

    /// dl-core 1.10: the page's download tap was a no-op for a catalogue book this device had
    /// never fetched. It goes through ``LibraryModel/keepOffline(_:queue:)``, whose remote
    /// route queues the entry on the one app-level queue — so the tap starts a transfer the
    /// queue can pause, resume and resume after a relaunch.
    @Test("The page's download tap goes through the queue rather than copying a file")
    func thePagesDownloadTapReachesTheQueue() {
        let actions = LibraryFeatureSource.code(of: "Sources/LibraryFeature/DetailActions.swift")
        let keep = LibraryFeatureSource.code(of: "Sources/LibraryFeature/KeepOffline.swift")

        #expect(actions.contains("await model.keepOffline([publication.id])"))
        #expect(keep.contains("queue: DownloadQueue = .shared()"))
        #expect(keep.contains("RemoteMemberResolution.enqueue("))
    }
}
