import Foundation
import Testing

@testable import LibraryFeature
import Catalogue
import Persistence
import StoryArcCore

/// A kept Kavita chapter is a download like any other — `offline-downloads` 1.9.
///
/// It was not. `KavitaKeep` fetched the whole body into a `Data`, wrote it to a cache file and
/// moved it into the download store itself, so the chapter had no row in the downloads view
/// and none of the pause, resume, retry or concurrency bound *Queue management* asks for.
///
/// Three claims, and the third is the one the ordering problem turns on: the destination's
/// extension is chosen before the file lands, Kavita states the type only in the response, and
/// an EPUB written under `.cbz` reaches the comic reader.
@Suite("A Kavita chapter goes through the download queue")
@MainActor
struct KavitaChapterQueueTests {
    private let chapterID = "kavita:4F1B0C7E-0000-0000-0000-00000000ABCD:3103"

    private func store() throws -> DownloadStore {
        let name = "kavita-chapter-queue-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        return DownloadStore(defaults: defaults, directory: directory)
    }

    private func queue(over store: DownloadStore) -> DownloadQueue {
        DownloadQueue(store: store, settings: { AppSettings(downloadOverWifiOnly: false) })
    }

    private var remote: URL {
        URL(string: "https://kavita.invalid/api/Download/chapter?chapterId=3103")!
    }

    @Test("A chapter the reader keeps becomes a record the queue owns")
    func chapterBecomesAQueuedRecord() async throws {
        let queue = queue(over: try store())

        Task {
            _ = await queue.fetchChapter(
                id: chapterID,
                title: "Harbour Lights 03",
                from: remote,
                sourceID: nil,
                credential: .bearer(token: "session-token"),
                seriesHint: "Harbour Lights"
            )
        }
        await Task.yield()
        await Task.yield()

        let record = try #require(queue.library[chapterID])
        #expect(record.title == "Harbour Lights 03")
        // Nothing guessed. The server names the type in the response, and the record says so
        // by saying nothing until it has one.
        #expect(record.mediaType.isEmpty)
    }

    @Test("The chapter's own request carries the token handed in at enqueue")
    func tokenTravelsWithTheChapter() async throws {
        let queue = queue(over: try store())

        Task {
            _ = await queue.fetchChapter(
                id: chapterID,
                title: "Harbour Lights 03",
                from: remote,
                sourceID: nil,
                credential: .bearer(token: "session-token")
            )
        }
        await Task.yield()
        await Task.yield()

        let record = try #require(queue.library[chapterID])
        let request = try queue.attemptRequest(for: record)
        // The secure store holds the API key, which this route refuses. Only the token the
        // client minted gets the bytes.
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
    }

    @Test("A landed chapter is named from its bytes when the record names no format")
    func landedChapterIsNamedFromItsBytes() async throws {
        let store = try store()
        let queue = queue(over: store)
        let download = Download(
            id: chapterID,
            title: "Harbour Lights 03",
            remote: remote,
            mediaType: ""
        )
        queue.record(download)

        let arrived = FileManager.default.temporaryDirectory
            .appending(path: "kavita-landing-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: epubFixture, to: arrived)

        let landed = try await queue.land(download, from: arrived)

        #expect(landed.pathExtension == "epub")
        #expect(queue.library[chapterID]?.mediaType == "application/epub+zip")
    }

    /// One real EPUB from the shared corpus, which is the only thing that can answer "what
    /// are these bytes" honestly. Resolved from `#filePath` for `FixtureCorpus`'s reason: SPM
    /// cannot declare a resource outside its own package root.
    private var epubFixture: URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let corpus = directory.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: corpus.appending(path: "manifest.json").path) {
                return corpus.appending(path: "ebooks/declared-rtl.epub")
            }
            directory = directory.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }
}
