import Foundation
import Testing

import Formats
import Persistence
import StoryArcCore
@testable import ReaderFeature

/// A stream that has lost its connection: the pages are known, and every read fails.
///
/// A read that succeeds after the watch returns can only come from the local copy.
private struct Unplugged: ComicArchiveReading {
    struct Gone: Error {}

    let pages: [PageEntry]
    var skippedPageCount: Int { 0 }

    func data(for page: PageEntry) async throws -> Data { throw Gone() }
}

/// The adoption watch and the streamed open start in parallel, from two `.task`s in
/// `ReaderLifecycle`, so the watch runs before `open` sets `archive`.
///
/// Before the fix the watch read `archive` once, found nothing and returned. The reader then
/// never took the local copy. This suite starts the watch first and sets `archive` later.
@MainActor
@Suite("Reader adoption")
struct ReaderAdoptionTests {
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
        let landed: URL
    }

    /// A reader streaming from a catalogue address, and a store with a finished copy of it.
    private func fixture() throws -> Fixture {
        let suite = "app.storyarc.tests.adoption.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = URL.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        let store = DownloadStore(defaults: defaults, directory: directory)

        let remote = try #require(URL(string: "https://catalogue.test/entries/bone"))
        let id = "urn:uuid:bone"
        store.save(DownloadLibrary(downloads: [
            Download(id: id, title: "Bone", remote: remote, mediaType: Self.cbz, state: .finished),
        ]))
        try store.prepare()
        let landed = store.location(for: id, mediaType: Self.cbz, title: "Bone")
        try FileManager.default.createDirectory(
            at: landed.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: Self.corpus.appending(path: "comics/natural-sort.cbz"), to: landed
        )

        let model = ReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: remote.absoluteString),
                format: .cbz,
                displayTitle: "Bone",
                origin: .inferred
            ),
            url: remote
        )
        return Fixture(store: store, model: model, landed: landed)
    }

    @Test("A watch that starts before the open takes the copy once the archive is set",
          .timeLimit(.minutes(1)))
    func watchStartedBeforeOpenAdopts() async throws {
        let fixture = try fixture()
        defer { fixture.store.reset() }
        let watching = Task { await fixture.model.adoptTheCopyWhenItArrives(store: fixture.store) }
        // The watch has to see an unopened reader first. That is the race the fix closes.
        try await Task.sleep(for: .milliseconds(50))

        let local = try await ComicArchiveOpener.open(fileAt: fixture.landed)
        let stream = AdoptingArchive(Unplugged(pages: local.pages))
        fixture.model.archive = stream
        await watching.value

        let page = try #require(stream.pages.first)
        #expect(try await stream.data(for: page).isEmpty == false)
    }
}
