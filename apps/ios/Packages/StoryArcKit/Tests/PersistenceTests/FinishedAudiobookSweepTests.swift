import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

/// `audiobooks-and-playback` task 7.3: a finished audiobook reaches the sweep.
///
/// The player writes a listening record for the book's own file, and the app's sweep asks the
/// progress store about each finished download by that file's path. Nothing had put the two
/// together for an audiobook, so this drives them as the app does: a real store, a record the
/// way `StoryArcAppActions.wirePlayerRecording` writes one, and the question the sweep asks.
/// Android's half is `FinishedAudiobookSweepTest`.
@Suite("A finished audiobook's download is swept", .serialized)
struct FinishedAudiobookSweepTests {
    private func store(_ name: String) -> DownloadStore {
        let directory = URL.temporaryDirectory.appending(path: "storyarc-audiobook-sweep-\(name)")
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return DownloadStore(
            defaults: UserDefaults(suiteName: "audiobook-sweep-\(name)") ?? .standard,
            directory: directory
        )
    }

    private func audiobook(in store: DownloadStore) -> (library: DownloadLibrary, path: String) {
        let download = Download(
            id: "sea-room",
            title: "Sea Room",
            remote: URL(fileURLWithPath: "/fixtures/sea-room"),
            mediaType: "audio/mp4",
            state: .finished,
            downloadedBytes: 3
        )
        let file = store.location(of: download)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data([1, 2, 3]).write(to: file)
        return (DownloadLibrary(downloads: [download]), file.path)
    }

    private func heard(_ path: String, finished: Bool, in progress: ProgressStore) async throws {
        try await progress.save(
            ReadingProgress(
                identity: PublicationIdentity(normalizedPath: path),
                position: .listening(part: 2, partCount: 3, offset: 60, of: 60),
                isFinished: finished,
                updatedAt: .now
            )
        )
    }

    @Test("A listening record that is finished sweeps the audiobook's download")
    func finishedIsSwept() async throws {
        let store = store("finished")
        let (library, path) = audiobook(in: store)
        let progress = try ProgressStore.inMemory()
        try await heard(path, finished: true, in: progress)

        let found = await store.finishedDownload(in: library, progress: progress)

        #expect(found?.id == "sea-room")
    }

    @Test("A listening record that is not finished leaves the download alone")
    func unfinishedIsKept() async throws {
        let store = store("unfinished")
        let (library, path) = audiobook(in: store)
        let progress = try ProgressStore.inMemory()
        try await heard(path, finished: false, in: progress)

        #expect(await store.finishedDownload(in: library, progress: progress) == nil)
    }

    @Test("A book nobody listened to is not swept")
    func unheardIsKept() async throws {
        let store = store("unheard")
        let (library, _) = audiobook(in: store)

        #expect(await store.finishedDownload(in: library, progress: try ProgressStore.inMemory()) == nil)
    }

    @Test("A finished book the reader kept is skipped")
    func keptIsSkipped() async throws {
        let store = store("kept")
        let (library, path) = audiobook(in: store)
        let progress = try ProgressStore.inMemory()
        try await heard(path, finished: true, in: progress)

        let found = await store.finishedDownload(in: library, isKept: { $0 == "sea-room" }, progress: progress)

        #expect(found == nil)
    }
}
