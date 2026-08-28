import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

@Suite("Download store")
struct DownloadStoreTests {
    /// A store of its own, so tests do not read each other's downloads.
    private struct Fixture {
        let store: DownloadStore
        let directory: URL
    }

    private func fixture() throws -> Fixture {
        let name = "app.storyarc.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = URL.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        return Fixture(
            store: DownloadStore(defaults: defaults, directory: directory),
            directory: directory
        )
    }

    private func download(_ id: String) -> Download {
        Download(
            id: id,
            title: id,
            remote: URL(fileURLWithPath: "/\(id).epub"),
            mediaType: "application/epub+zip"
        )
    }

    @Test("An empty store has an empty library")
    func emptyStore() throws {
        let store = try fixture().store
        #expect(store.library().downloads.isEmpty)
    }

    @Test("What is saved comes back")
    func roundTrip() throws {
        let store = try fixture().store
        var library = DownloadLibrary().queueing(download("a")).queueing(download("b"))
        library = library.advancing("a", downloaded: 120, expected: 120).marking("a", as: .finished)
        store.save(library)

        let read = store.library()
        #expect(read.downloads.map(\.id) == ["a", "b"])
        #expect(read["a"]?.state == .finished)
        #expect(read["a"]?.expectedBytes == 120)
        #expect(read["a"]?.completedAt != nil)
    }

    @Test("A download that was running comes back queued")
    func runningIsNotDurable() throws {
        // "Running" describes a transfer, and a transfer does not survive the process that
        // was doing it. Read back as running, the queue would wait for bytes nobody is
        // fetching.
        let store = try fixture().store
        store.save(DownloadLibrary().queueing(download("a")).marking("a", as: .running))
        #expect(store.library()["a"]?.state == .queued)
    }

    @Test("A failure and its count are durable")
    func failureIsDurable() throws {
        // The count is what stops the third attempt from being the first attempt again.
        let store = try fixture().store
        store.save(DownloadLibrary().queueing(download("a")).failing("a", reason: "timed out"))
        #expect(store.library()["a"]?.state == .failed(reason: "timed out", attempts: 1))
    }

    @Test("The directory is made and kept out of backups")
    func directoryIsExcluded() throws {
        // `offline-downloads`: downloads "are excluded from device backups, because they
        // are re-downloadable and would otherwise dominate a backup".
        let fixture = try fixture()
        let store = fixture.store
        let directory = fixture.directory
        defer { store.reset() }
        try store.prepare()
        #expect(FileManager.default.fileExists(atPath: directory.path()))
        let excluded = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(excluded.isExcludedFromBackup == true)
    }

    @Test("A path is unique by identity, whatever the publication is called")
    func uniqueByIdentity() throws {
        // Two catalogues can offer the same title. A collision hands the reader the wrong
        // book, which is worse than any name they might have preferred. The identity is the
        // *directory* now, so the file can carry the publication's own name -- which is
        // what the indexer reads a title and a series out of -- and still not collide.
        let store = try fixture().store
        let one = store.location(for: "urn:uuid:1", extension: "cbz", named: "Bone")
        let other = store.location(for: "urn:uuid:2", extension: "cbz", named: "Bone")
        #expect(one != other)
        #expect(one.lastPathComponent == "Bone.cbz")
        #expect(one.deletingLastPathComponent().lastPathComponent == "urn-uuid-1")
    }

    @Test("A name a filesystem would choke on is made safe")
    func namesAreMadeSafe() throws {
        // A server's title is a server's, and a slash in one would make a directory.
        let store = try fixture().store
        let location = store.location(for: "urn:uuid:1/2 3", extension: "epub")
        #expect(location.lastPathComponent == "urn-uuid-1-2 3.epub")
        #expect(!location.deletingLastPathComponent().lastPathComponent.contains("/"))
    }

    @Test("Bytes on disk are counted from the disk")
    func bytesAreCountedFromDisk() throws {
        // Not from the record. The system can reclaim a file, and a storage total that
        // counts bytes nobody has makes a reader distrust the whole screen.
        let store = try fixture().store
        defer { store.reset() }
        try store.prepare()
        let file = store.location(for: "a", extension: "cbz")
        // The id is a directory now, so the fixture makes it like the queue does.
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: 300).write(to: file)
        #expect(store.bytesOnDisk() == 300)
    }
}
