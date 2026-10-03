import Foundation
import Testing

import Formats
import Persistence
import StoryArcCore
@testable import ReaderFeature

/// `offline-downloads` dl-core 1.7: a streamed open that fails is replaced by the copy that
/// lands, rather than left showing the ordinary failure for ever.
///
/// Before the fix, a server with no range support left `ReaderModel.archive` nil for good —
/// `open(maxPixelSize:)` set `failure`, and `adoptTheCopyWhenItArrives()` only ever looked for
/// an `AdoptingArchive` to swap bytes *into*. With none, the watch polled for ever and did
/// nothing, so the reader stayed on the generic failure even after the download finished.
@MainActor
@Suite("Reader waits for a download rather than failing")
struct ReaderDownloadWaitTests {
    private static let cbz = "application/vnd.comicbook+zip"

    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: candidate.appending(path: "manifest.json").path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    private struct Fixture {
        let store: DownloadStore
        let model: ReaderModel
        let remote: URL
        let id: String
    }

    /// A reader streaming from a catalogue address with no `HttpSource` registered in this
    /// test target, so the open genuinely fails — and a store recording that this exact
    /// address is still on its way.
    private func fixture() throws -> Fixture {
        let suite = "app.storyarc.tests.downloadwait.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = URL.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        let store = DownloadStore(defaults: defaults, directory: directory)

        let remote = try #require(URL(string: "https://catalogue.test/entries/waiting-room"))
        let id = "urn:uuid:waiting-room"
        store.save(DownloadLibrary(downloads: [
            Download(id: id, title: "Waiting Room", remote: remote, mediaType: Self.cbz, state: .queued),
        ]))

        let model = ReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: remote.absoluteString),
                format: .cbz,
                displayTitle: "Waiting Room",
                origin: .inferred
            ),
            url: remote
        )
        return Fixture(store: store, model: model, remote: remote, id: id)
    }

    @Test("A stream that cannot open waits rather than showing the ordinary failure")
    func failedStreamWaitsWhileDownloadIsPending() async throws {
        let fixture = try fixture()
        defer { fixture.store.reset() }

        await fixture.model.open(maxPixelSize: 256, downloadStore: fixture.store)

        #expect(fixture.model.isWaitingForDownload)
        #expect(fixture.model.failure == nil)
    }

    @Test("A stream that cannot open fails ordinarily once the download itself has failed")
    func failedStreamFailsOnceDownloadHasFailed() async throws {
        let fixture = try fixture()
        defer { fixture.store.reset() }
        fixture.store.save(DownloadLibrary(downloads: [
            Download(
                id: fixture.id, title: "Waiting Room", remote: fixture.remote, mediaType: Self.cbz,
                state: .failed(reason: "no network", attempts: 3)
            ),
        ]))

        await fixture.model.open(maxPixelSize: 256, downloadStore: fixture.store)

        #expect(fixture.model.isWaitingForDownload == false)
        #expect(fixture.model.failure != nil)
    }

    @Test("The wait ends as the ordinary failure when the download fails after it began",
          .timeLimit(.minutes(1)))
    func waitEndsWhenTheDownloadFails() async throws {
        let fixture = try fixture()
        defer { fixture.store.reset() }

        await fixture.model.open(maxPixelSize: 256, downloadStore: fixture.store)
        #expect(fixture.model.isWaitingForDownload)

        fixture.store.save(DownloadLibrary(downloads: [
            Download(
                id: fixture.id, title: "Waiting Room", remote: fixture.remote, mediaType: Self.cbz,
                state: .failed(reason: "no network", attempts: 3)
            ),
        ]))
        await fixture.model.adoptTheCopyWhenItArrives(store: fixture.store)

        #expect(fixture.model.isWaitingForDownload == false)
        #expect(fixture.model.failure != nil)
    }

    @Test("The watch opens the local copy directly once it lands, with nothing to adopt into",
          .timeLimit(.minutes(1)))
    func watchOpensTheLocalCopyAfterAFailedStream() async throws {
        let fixture = try fixture()
        defer { fixture.store.reset() }

        await fixture.model.open(maxPixelSize: 256, downloadStore: fixture.store)
        #expect(fixture.model.isWaitingForDownload)

        try fixture.store.prepare()
        let landed = fixture.store.location(for: fixture.id, mediaType: Self.cbz, title: "Waiting Room")
        try FileManager.default.createDirectory(
            at: landed.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: Self.corpus.appending(path: "comics/natural-sort.cbz"), to: landed
        )
        fixture.store.save(DownloadLibrary(downloads: [
            Download(
                id: fixture.id, title: "Waiting Room", remote: fixture.remote, mediaType: Self.cbz,
                state: .finished
            ),
        ]))

        let watching = Task { await fixture.model.adoptTheCopyWhenItArrives(store: fixture.store) }
        await watching.value

        #expect(fixture.model.isWaitingForDownload == false)
        #expect(fixture.model.pages.isEmpty == false)
        #expect(fixture.model.failure == nil)
    }
}
