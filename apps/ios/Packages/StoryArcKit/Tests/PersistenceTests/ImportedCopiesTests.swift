import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

@Suite("Imported copies")
struct ImportedCopiesTests {
    /// A store and an original file, each in a directory of its own so tests do not read
    /// each other's copies.
    private struct Fixture {
        let store: DownloadStore
        let original: URL
        let elsewhere: URL
    }

    private func fixture(named name: String = "Bone 01.cbz", bytes: Int = 512) throws -> Fixture {
        let suite = "app.storyarc.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = URL.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        let elsewhere = root.appending(path: "elsewhere", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let original = elsewhere.appending(path: name)
        try Data(count: bytes).write(to: original)
        return Fixture(
            store: DownloadStore(
                defaults: defaults,
                directory: root.appending(path: "Downloads", directoryHint: .isDirectory)
            ),
            original: original,
            elsewhere: elsewhere
        )
    }

    @Test("An imported file is copied into app storage and recorded")
    func importCopiesAndRecords() throws {
        // `local-library`: an imported file "is copied into app storage, indexed, and listed
        // under an 'On this device' source". The indexing is the library's; the copy and the
        // record are this store's.
        let fixture = try fixture()
        defer { fixture.store.reset() }

        let copy = try fixture.store.importing(fixture.original, into: DownloadLibrary())

        #expect(FileManager.default.fileExists(atPath: copy.file.path))
        #expect(copy.file.path != fixture.original.path)
        #expect(copy.download.sourceID == ImportedCopies.sourceID)
        #expect(copy.download.state == .finished)
        #expect(copy.bytes == 512)
        // The reader's own name for the book, not its identifier: the indexer reads a title
        // and a series out of a filename, so the copy has to keep one.
        #expect(copy.file.lastPathComponent == "Bone 01.cbz")
    }

    @Test("The record and the file agree about where the copy is")
    func recordFindsItsFile() throws {
        // The store chose the path when it wrote the file and has to choose the same one to
        // find it again — which is only true if the media type round-trips to an extension.
        let fixture = try fixture(named: "Maus.epub")
        defer { fixture.store.reset() }

        let copy = try fixture.store.importing(fixture.original, into: DownloadLibrary())
        #expect(fixture.store.location(of: copy.download) == copy.file)
    }

    @Test("The copy outlives the original")
    func copySurvivesTheOriginal() throws {
        // The whole point of the requirement: the copy "survives the original being moved
        // or deleted".
        let fixture = try fixture()
        defer { fixture.store.reset() }

        let copy = try fixture.store.importing(fixture.original, into: DownloadLibrary())
        try FileManager.default.removeItem(at: fixture.original)

        #expect(FileManager.default.fileExists(atPath: copy.file.path))
        #expect(fixture.store.library()[copy.download.id] != nil)
    }

    @Test("Importing the same file twice is one copy")
    func importingTwiceIsOneCopy() throws {
        // A reader who taps Import on a comic they imported last week gets the copy they
        // already have, not a second one beside it weighing the same.
        let fixture = try fixture()
        defer { fixture.store.reset() }

        let first = try fixture.store.importing(fixture.original, into: DownloadLibrary())
        let second = try fixture.store.importing(fixture.original, into: first.library)

        #expect(second.library.downloads.count == 1)
        #expect(second.download.id == first.download.id)
        #expect(second.file == first.file)
    }

    @Test("A format StoryArc does not read is refused by name")
    func unsupportedIsRefusedByName() throws {
        // `local-library` forbids a generic failure. A reader who picked the wrong file has
        // no way to tell that from a broken app unless the app says which it is.
        let fixture = try fixture(named: "notes.txt")
        defer { fixture.store.reset() }

        #expect(throws: ImportedCopies.ImportError.unsupported("TXT")) {
            _ = try fixture.store.importing(fixture.original, into: DownloadLibrary())
        }
    }

    @Test("What the copies weigh is counted from the disk")
    func spaceUsedIsCountedFromDisk() throws {
        // `local-library` asks the app to report the space used, and a total taken from the
        // record would claim bytes the system may already have reclaimed.
        let fixture = try fixture(bytes: 900)
        defer { fixture.store.reset() }

        _ = try fixture.store.importing(fixture.original, into: DownloadLibrary())
        #expect(fixture.store.bytesOnDisk() == 900)
    }

    @Test("An imported copy is never swept away by finishing it")
    func finishingDoesNotSweepAnImport() throws {
        // `offline-downloads` removes a finished download because the catalogue can be asked
        // for it again. Nothing can be asked for an import, so removing one on the last page
        // would be the app breaking `local-library`'s own promise.
        let fixture = try fixture()
        defer { fixture.store.reset() }

        let copy = try fixture.store.importing(fixture.original, into: DownloadLibrary())
        let swept = fixture.store.finishedDownload(in: copy.library) { _ in true }
        #expect(swept == nil)
    }

    @Test("A download is still swept away by finishing it")
    func finishingStillSweepsADownload() throws {
        // The other half of the same guard: excluding imports must not have excluded
        // everything.
        let fixture = try fixture()
        defer { fixture.store.reset() }

        let fetched = Download(
            id: "urn:uuid:1",
            sourceID: UUID(),
            title: "Bone 02",
            remote: try #require(URL(string: "https://example.test/bone-02.cbz")),
            mediaType: "application/vnd.comicbook+zip"
        )
        let library = DownloadLibrary().queueing(fetched).marking(fetched.id, as: .finished)
        #expect(fixture.store.finishedDownload(in: library) { _ in true }?.id == fetched.id)
    }

    @Test("The identity of a copy does not move with the original")
    func identityIsNotAPath() {
        // Keyed on the original's name and size rather than its path, because the copy is
        // promised to outlive the original being *moved* — and a path-keyed identity would
        // make the same comic a second import the moment its owner tidied a folder.
        #expect(
            ImportedCopies.identity(name: "Bone 01.cbz", bytes: 512)
                == ImportedCopies.identity(name: "Bone 01.cbz", bytes: 512)
        )
        #expect(
            ImportedCopies.identity(name: "Bone 01.cbz", bytes: 512)
                != ImportedCopies.identity(name: "Bone 02.cbz", bytes: 512)
        )
    }
}
