import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// What the imported copies weigh, and who is told.
///
/// `local-library`'s *Importing* scenario ends "**AND** the app reports the space used", and
/// `offline-downloads`' *Storage view* asks for the total "broken down by source". "On this
/// device" is a source, and ``LibraryModel/importedBytes`` is its share.
///
/// **The accessor existed and nothing read it.** It was declared on 2026-08-30 and referenced
/// by no screen and no test on either platform until the storage row was added, so the figure
/// reached a reader only inside the downloads total, under a label that says downloads.
/// `ImportedStorageRowTests` asserts the row that states it; this suite asserts the number.
///
/// Android's `ImportedBytesTest` asserts the same three claims against `LibraryViewModel`.
@Suite("Imported storage")
@MainActor
struct ImportedStorageTests {

    /// A store of its own, and originals of their own, so no case reads another's copies.
    private struct Fixture {
        let store: DownloadStore
        let elsewhere: URL
    }

    private func fixture() throws -> Fixture {
        let suite = "app.storyarc.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = URL.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        let elsewhere = root.appending(path: "elsewhere", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        return Fixture(
            store: DownloadStore(
                defaults: defaults,
                directory: root.appending(path: "Downloads", directoryHint: .isDirectory)
            ),
            elsewhere: elsewhere
        )
    }

    @discardableResult
    private func imported(_ name: String, bytes: Int, in fixture: Fixture) throws -> ImportedCopy {
        let original = fixture.elsewhere.appending(path: name)
        try Data(count: bytes).write(to: original)
        return try fixture.store.importing(original, into: fixture.store.library())
    }

    @Test("Nothing imported weighs nothing")
    func emptyIsZero() throws {
        let fixture = try fixture()
        defer { fixture.store.reset() }
        let model = LibraryModel(downloadStore: fixture.store)

        #expect(model.importedBytes == 0)
    }

    @Test("Every imported copy is counted")
    func everyCopyCounts() throws {
        let fixture = try fixture()
        defer { fixture.store.reset() }
        try imported("Bone 01.cbz", bytes: 512, in: fixture)
        try imported("Bone 02.cbz", bytes: 1_024, in: fixture)
        let model = LibraryModel(downloadStore: fixture.store)

        #expect(model.importedBytes == 1_536, """
            The imported copies do not add up. This is the figure the storage row states, so \
            a reader reads it beside the downloads total and subtracts one from the other.
            """)
    }

    @Test("A download the app fetched is not counted as an imported copy")
    func fetchedIsNotImported() throws {
        // The half that makes the row worth drawing. A figure that counted everything in the
        // downloads directory would be the total that is already on the screen above it.
        let fixture = try fixture()
        defer { fixture.store.reset() }
        try imported("Bone 01.cbz", bytes: 512, in: fixture)

        let fetched = Download(
            id: "fetched",
            sourceID: UUID(),
            title: "Maus",
            remote: URL(filePath: "/nowhere/maus.epub"),
            mediaType: "application/epub+zip",
            expectedBytes: 4_096,
            downloadedBytes: 4_096
        )
        fixture.store.save(
            fixture.store.library().queueing(fetched).marking(fetched.id, as: .finished)
        )
        let model = LibraryModel(downloadStore: fixture.store)

        #expect(model.importedBytes == 512, """
            A download the reader fetched from a source was counted as an imported copy. \
            "On this device" is the source the copies are filed under, and a fetched \
            publication is filed under the source it came from.
            """)
    }

    @Test("A library with no download store reports nothing rather than refusing")
    func noStoreIsZero() {
        // Every host test builds a model without one, and a storage figure is not worth a
        // crash: the honest answer for an app that owns no copies is that they weigh nothing.
        #expect(LibraryModel().importedBytes == 0)
    }
}
