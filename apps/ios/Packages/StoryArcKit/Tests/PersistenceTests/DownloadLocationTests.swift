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

    /// `publication-formats`: "an MP3 is not written back as an M4B, because a player handed a
    /// file whose extension disagrees with its bytes is a failure the listener sees and cannot
    /// explain". Every audio download was written as `Sea Room.bin` while the format table
    /// held one flat audiobook case, because that case answered no media type to read back.
    @Test("An audiobook is written under the extension of the container it is")
    func audioKeepsItsContainer() throws {
        let (store, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }

        let expected = [
            "audio/mpeg": "Sea Room.mp3",
            "audio/mp4": "Sea Room.m4b",
            "audio/flac": "Sea Room.flac",
            "audio/ogg": "Sea Room.ogg",
        ]
        for (mediaType, name) in expected {
            let path = store.location(for: "urn:storyarc:9", mediaType: mediaType, title: "Sea Room")
            #expect(path.lastPathComponent == name)
        }
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

    @Test("A resume token sits inside its own download's folder and a removal takes it")
    func removalTakesTheResumeToken() throws {
        let (store, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = download()

        // `offline-downloads` resumes an interrupted download "from where it stopped", and on
        // iOS this token is what the system needs to do it. A reader who removes a download
        // and is left with the makings of half of one has been told the bytes are gone when
        // they are not.
        let token = store.resumeData(of: record)
        try FileManager.default.createDirectory(
            at: token.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data([4, 5, 6]).write(to: token)

        #expect(
            token.deletingLastPathComponent() == store.location(of: record)
                .deletingLastPathComponent(),
            "The resume token is not in the folder a removal deletes."
        )
        store.remove(record)
        #expect(!FileManager.default.fileExists(atPath: token.path()))
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

    /// A download written under a name this build no longer computes still resolves.
    ///
    /// The extension is computed from the media type on every call, so giving audio its
    /// media types on 2026-09-07 renamed the computed path of every audiobook already on a
    /// device from `Title.bin` to `Title.mp3`. Nothing renamed the file. Without this the
    /// book stopped opening, kept its on-device mark, and went on being counted by
    /// `bytesOnDisk()` with nothing able to remove it.
    @Test("A file already on disk outranks the extension this build would compute")
    func anOlderExtensionStillResolves() throws {
        let (store, directory) = try store()
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = "urn:storyarc:audio"
        let computed = store.location(for: id, mediaType: "audio/mpeg", title: "Sea Room")
        #expect(computed.pathExtension == "mp3", "this build computes the container's extension")

        // What a build before the audio split left on disk: every audio type fell to `bin`.
        let aged = computed.deletingPathExtension().appendingPathExtension("bin")
        try FileManager.default.createDirectory(
            at: aged.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data([1, 2, 3]).write(to: aged)

        let resolved = store.location(for: id, mediaType: "audio/mpeg", title: "Sea Room")
        #expect(resolved.lastPathComponent == "Sea Room.bin", "the file on disk was not found")
    }
}
