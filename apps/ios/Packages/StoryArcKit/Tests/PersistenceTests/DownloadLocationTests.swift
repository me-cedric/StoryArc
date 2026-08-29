import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

/// That a download is written where a removal will look for it.
///
/// The defect this pins: the queue named the file after the publication and the Settings
/// screen deleted the one named after the identifier, so removing a download dropped the
/// record, left the bytes, and the storage total on that same screen never went down.
///
/// Mirrors Android's `DownloadLocationTest`.
@Suite("Download locations")
struct DownloadLocationTests {

    private func store() throws -> (DownloadStore, URL) {
        let directory = URL.temporaryDirectory.appending(path: "downloads-\(UUID().uuidString)")
        let defaults = try #require(UserDefaults(suiteName: directory.lastPathComponent))
        return (DownloadStore(defaults: defaults, directory: directory), directory)
    }

    private func download(id: String = "urn:storyarc:6", title: String = "Bone 6") -> Download {
        Download(
            id: id,
            title: title,
            remote: URL(filePath: "/tmp/\(id)"),
            mediaType: "application/vnd.comicbook+zip",
            state: .finished,
            downloadedBytes: 3
        )
    }

    @Test("The path a download is written to is the path it is looked for at")
    func writeAndReadAgree() throws {
        let (store, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = download()

        #expect(store.location(of: record) == store.location(
            for: record.id, mediaType: record.mediaType, title: record.title
        ))
    }

    @Test("The file is named after the publication, not after its identifier")
    func namedAfterTheTitle() throws {
        let (store, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A reader recognises "Bone 6"; nobody recognises `urn-storyarc-6`. The indexer also
        // reads a title and a series back out of the filename.
        #expect(store.location(of: download()).lastPathComponent == "Bone 6.cbz")
    }

    @Test("Removing takes the bytes, whatever the file inside happened to be called")
    func removalIgnoresTheStem() throws {
        let (store, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = download()

        // Written the way a build before this one wrote it: under the identifier.
        let old = store.location(for: record.id, mediaType: record.mediaType, title: record.id)
        try FileManager.default.createDirectory(
            at: old.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data([1, 2, 3]).write(to: old)
        #expect(FileManager.default.fileExists(atPath: old.path()))

        store.remove(record)
        #expect(!FileManager.default.fileExists(atPath: old.path()))
        #expect(!FileManager.default.fileExists(atPath: store.location(of: record).path()))
    }

    @Test("A title a filesystem would refuse is made safe without leaving its own folder")
    func awkwardTitlesAreSafe() throws {
        let (store, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }
        let awkward = download(title: #"Bone: Out/From "Boneville""#)

        let file = store.location(of: awkward)
        #expect(!file.lastPathComponent.contains("/"))
        #expect(file.deletingLastPathComponent().lastPathComponent
            == store.location(of: download()).deletingLastPathComponent().lastPathComponent)
    }

    @Test("A download with no title falls back to its identity rather than to nothing")
    func emptyTitleFallsBack() throws {
        let (store, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(store.location(of: download(title: "  ")).lastPathComponent == "urn-storyarc-6.cbz")
    }
}
