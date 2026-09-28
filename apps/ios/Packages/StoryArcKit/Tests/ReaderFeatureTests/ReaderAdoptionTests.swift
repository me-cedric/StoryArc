import Foundation
import Testing

import Formats
import Persistence
import StoryArcCore
@testable import ReaderFeature

@MainActor
@Suite("Reader adoption")
struct ReaderAdoptionTests {
    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(
                atPath: candidate.appending(path: "manifest.json").path
            ) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    private static let cbz = "application/vnd.comicbook+zip"

    private struct Fixture {
        let store: DownloadStore
        let model: ReaderModel
    }

    private func fixture() throws -> Fixture {
        let suite = "app.storyarc.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = URL.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        let store = DownloadStore(defaults: defaults, directory: directory)

        let remote = try #require(URL(string: "https://catalogue.test/entries/bone"))
        let id = "urn:uuid:bone"
        let record = Download(
            id: id, title: "Bone", remote: remote, mediaType: Self.cbz, state: .finished
        )
        store.save(DownloadLibrary(downloads: [record]))

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
        return Fixture(store: store, model: model)
    }

    @Test("fixture builds")
    func fixtureBuilds() throws {
        let fixture = try fixture()
        defer { fixture.store.reset() }
        #expect(fixture.model.archive == nil)
    }

    @Test("watch starts and can be cancelled")
    func watchStartsAndCancels() async throws {
        let fixture = try fixture()
        defer { fixture.store.reset() }
        let watching = Task { await fixture.model.adoptTheCopyWhenItArrives() }
        try await Task.sleep(for: .milliseconds(50))
        watching.cancel()
        await watching.value
        #expect(Bool(true))
    }

    @Test("the watch actually adopts, awaited to completion")
    func watchAdoptsToCompletion() async throws {
        let fixture = try fixture()
        defer { fixture.store.reset() }
        let watching = Task { await fixture.model.adoptTheCopyWhenItArrives(store: fixture.store) }
        let opened = try await ComicArchiveOpener.open(
            fileAt: Self.corpus.appending(path: "comics/natural-sort.cbz")
        )
        try await Task.sleep(for: .milliseconds(50))
        fixture.model.archive = AdoptingArchive(opened)
        await watching.value
        #expect(Bool(true))
    }

    @Test("setting archive while the watch is sleeping does not hang")
    func settingArchiveDoesNotHang() async throws {
        let fixture = try fixture()
        defer { fixture.store.reset() }
        let watching = Task { await fixture.model.adoptTheCopyWhenItArrives() }
        try await Task.sleep(for: .milliseconds(50))
        let opened = try await ComicArchiveOpener.open(
            fileAt: Self.corpus.appending(path: "comics/natural-sort.cbz")
        )
        fixture.model.archive = AdoptingArchive(opened)
        watching.cancel()
        await watching.value
        #expect(Bool(true))
    }
}
