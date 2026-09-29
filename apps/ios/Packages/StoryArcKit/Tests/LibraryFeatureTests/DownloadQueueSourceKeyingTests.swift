import Foundation
import Testing

import Catalogue
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// An OPDS download is keyed by its source as well as its raw entry id.
///
/// dl-core 1.2: two catalogues that number their entries the same way — `entry-1`,
/// `entry-2` — shared one record and one file, because the queue kept a download only
/// under its entry id. A source removal (`removingAll(from:)`) found nothing to remove
/// either, for the same reason: the record carried no source at all.
///
/// Android asserts the same two claims in `DownloadQueueSourceKeyingTest`.
@Suite("An OPDS download carries its source")
@MainActor
struct DownloadQueueSourceKeyingTests {

    private func store() throws -> DownloadStore {
        let name = "download-source-keying-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        return DownloadStore(defaults: defaults, directory: directory)
    }

    @Test("Two sources that number their entries the same way are not the same record")
    func twoSourcesDoNotShareARecord() throws {
        let first = UUID()
        let second = UUID()
        let acquisition = OpdsAcquisition(
            href: URL(string: "https://example.invalid/entry-1.epub")!,
            mediaType: "application/epub+zip",
            kind: .open
        )
        let entry = OpdsEntry(id: "entry-1", title: "Harbour Lights 01")

        // Separate stores, on purpose: two catalogue queues writing one shared store without
        // clobbering each other is dl-core 1.1, not this task. What 1.2 owns is the key each
        // one writes under, which is what this asserts.
        let queueA = DownloadQueue(
            store: try store(), origin: nil, sourceID: first, settings: { AppSettings() }
        )
        let queueB = DownloadQueue(
            store: try store(), origin: nil, sourceID: second, settings: { AppSettings() }
        )

        queueA.enqueue(entry, using: acquisition)
        queueB.enqueue(entry, using: acquisition)

        #expect(queueA.downloadID(for: "entry-1") != queueB.downloadID(for: "entry-1"))
        #expect(queueA.library[queueA.downloadID(for: "entry-1")]?.sourceID == first)
        #expect(queueB.library[queueB.downloadID(for: "entry-1")]?.sourceID == second)
    }

    @Test("A queued download carries its source id, so a source removal finds it")
    func enqueuedDownloadCarriesItsSource() throws {
        let source = UUID()
        let queue = DownloadQueue(
            store: try store(), origin: nil, sourceID: source, settings: { AppSettings() }
        )
        queue.enqueue(
            OpdsEntry(id: "entry-9", title: "Harbour Lights 09"),
            using: OpdsAcquisition(
                href: URL(string: "https://example.invalid/entry-9.epub")!,
                mediaType: "application/epub+zip",
                kind: .open
            )
        )

        let (kept, removed) = queue.library.removingAll(from: source)
        #expect(removed.count == 1, "The removal found nothing, so it left the file behind.")
        #expect(kept.downloads.isEmpty)
    }

    @Test("The download id is namespaced by source, the way a Kavita chapter already is")
    func idIsNamespacedBySource() throws {
        let source = UUID()
        let queue = DownloadQueue(
            store: try store(), origin: nil, sourceID: source, settings: { AppSettings() }
        )
        #expect(queue.downloadID(for: "entry-3") == "opds:\(source.uuidString):entry-3")
    }

    @Test("A stray record this catalogue's origin owns is re-keyed when the queue opens")
    func strayRecordIsMigrated() throws {
        let origin = try #require(OpdsOrigin(url: URL(string: "https://library.example")!))
        let remote = URL(string: "https://library.example/download/entry-7.epub")!
        let store = try store()
        // What a pre-1.2 build wrote: no source, the bare entry id.
        store.save(
            DownloadLibrary(downloads: [
                Download(
                    id: "entry-7",
                    title: "Harbour Lights 07",
                    remote: remote,
                    mediaType: "application/epub+zip",
                    state: .finished,
                    downloadedBytes: 1_000
                )
            ])
        )

        let source = UUID()
        let queue = DownloadQueue(
            store: store,
            credential: { _ in nil },
            origin: origin,
            sourceID: source,
            settings: { AppSettings() }
        )

        let migrated = try #require(queue.library["opds:\(source.uuidString):entry-7"])
        #expect(migrated.sourceID == source)
        #expect(
            queue.library["entry-7"] == nil,
            "The old key is still readable, so a second source could still collide with it."
        )
        // The migration is written back, so a queue built again from the same store sees the
        // fixed record rather than migrating it a second time.
        #expect(store.library()["opds:\(source.uuidString):entry-7"] != nil)
    }

    @Test("A record from a different origin is left alone")
    func recordFromAnotherOriginIsNotMigrated() throws {
        let origin = try #require(OpdsOrigin(url: URL(string: "https://library.example")!))
        let elsewhere = URL(string: "https://elsewhere.invalid/entry-7.epub")!
        let store = try store()
        store.save(
            DownloadLibrary(downloads: [
                Download(
                    id: "entry-7",
                    title: "Harbour Lights 07",
                    remote: elsewhere,
                    mediaType: "application/epub+zip",
                    state: .finished,
                    downloadedBytes: 1_000
                )
            ])
        )

        let queue = DownloadQueue(
            store: store, origin: origin, sourceID: UUID(), settings: { AppSettings() }
        )

        #expect(queue.library["entry-7"] != nil, "A record this origin does not own was migrated anyway.")
    }
}
