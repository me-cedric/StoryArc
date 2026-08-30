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
        let one = store.location(for: "urn:uuid:1", mediaType: "application/vnd.comicbook+zip", title: "Bone")
        let other = store.location(for: "urn:uuid:2", mediaType: "application/vnd.comicbook+zip", title: "Bone")
        #expect(one != other)
        #expect(one.lastPathComponent == "Bone.cbz")
        #expect(one.deletingLastPathComponent().lastPathComponent == "urn-uuid-1")
    }

    @Test("A name a filesystem would choke on is made safe")
    func namesAreMadeSafe() throws {
        // A server's title is a server's, and a slash in one would make a directory.
        let store = try fixture().store
        let location = store.location(for: "urn:uuid:1/2 3", mediaType: "application/epub+zip", title: "")
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
        let file = store.location(for: "a", mediaType: "application/vnd.comicbook+zip", title: "")
        // The id is a directory now, so the fixture makes it like the queue does.
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: 300).write(to: file)
        #expect(store.bytesOnDisk() == 300)
    }

    @Test("A downloaded file is traced back to the source it came from")
    func attributesAFileToItsSource() throws {
        // `library-browsing` shows one library spanning every source, and a file on disk
        // carries no memory of the server it came from. The record does, and the directory
        // is what joins the two.
        let store = try fixture().store
        let server = UUID()
        let record = Download(
            id: "urn:uuid:7",
            sourceID: server,
            title: "Bone",
            remote: URL(fileURLWithPath: "/bone.cbz"),
            mediaType: "application/vnd.comicbook+zip",
            state: .finished
        )
        let library = DownloadLibrary(downloads: [record])

        let file = store.location(of: record)
        #expect(store.download(forFileAt: file, in: library)?.sourceID == server)
    }

    @Test("A file named something else in the same directory is still traced")
    func attributionFollowsTheDirectory() throws {
        // The writers have not always agreed on the file's name -- one path writes the
        // title, another the identifier -- and they have always agreed on the directory.
        // Matching on the name would lose half the library's attributions.
        let store = try fixture().store
        let record = Download(
            id: "urn:uuid:7",
            sourceID: UUID(),
            title: "Bone",
            remote: URL(fileURLWithPath: "/bone.cbz"),
            mediaType: "application/vnd.comicbook+zip",
            state: .finished
        )
        let library = DownloadLibrary(downloads: [record])

        // Named by identity, the way a build before the store owned the decision wrote
        // it. Matching is on the directory, so it is still this download's file.
        let renamed = store.location(
            for: record.id, mediaType: record.mediaType, title: record.id
        )
        #expect(store.download(forFileAt: renamed, in: library)?.id == record.id)
    }

    @Test("A file no download claims is attributed to nothing")
    func attributionRefusesToGuess() throws {
        let store = try fixture().store
        let stray = store.directory.appending(path: "elsewhere/Akira.cbz")
        #expect(store.download(forFileAt: stray, in: DownloadLibrary()) == nil)
    }

    // MARK: - A catalogue names the directory, so a catalogue can try to escape it

    @Test("An id of dots alone cannot name the directory above", arguments: ["..", ".", "...", "....."])
    func dotsCannotEscape(id: String) throws {
        let store = try fixture().store
        let file = store.location(for: id, mediaType: "application/vnd.comicbook+zip", title: "Akira")
        // The download's own directory, not its parent. An OPDS feed supplies the id
        // verbatim, so this is the one place that can refuse a hostile one.
        #expect(!file.path.contains("/../"))
        #expect(!file.deletingLastPathComponent().path.hasSuffix("/.."))
        #expect(file.path.hasPrefix(store.directory.path))
    }

    @Test("Removing a download named `..` leaves everything above it alone")
    func removeCannotReachOutside() throws {
        // A root this test owns, with the store one level inside it, so that the escape
        // this asserts against is one the filesystem would genuinely permit.
        let root = URL.temporaryDirectory.appending(path: "escape-\(UUID().uuidString)", directoryHint: .isDirectory)
        let downloads = root.appending(path: "Downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bystander = root.appending(path: "progress.sqlite")
        try Data("reading progress".utf8).write(to: bystander)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = DownloadStore(defaults: defaults, directory: downloads)

        store.remove(Download(
            id: "..",
            sourceID: UUID(),
            title: "Akira",
            remote: URL(fileURLWithPath: "/tmp/x.cbz"),
            mediaType: "application/vnd.comicbook+zip"
        ))

        #expect(FileManager.default.fileExists(atPath: bystander.path))
        #expect(FileManager.default.fileExists(atPath: downloads.path))
    }

}
