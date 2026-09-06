import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// A held download starts again from what it already fetched.
///
/// `offline-downloads`' *Resuming after interruption*: an interrupted download "resumes from
/// where it stopped if the server supports range requests, and restarts otherwise". Before
/// this, a pause for Wi-Fi kept the record and its `downloadedBytes` and threw the bytes
/// themselves away, so ten changes of connection on a 400 MB comic cost ten downloads.
///
/// **The two platforms reach this differently and the platform forces it.** Android holds the
/// fetched bytes in a partial file of its own and asks for the rest with a `Range` header,
/// which `OpdsRangeDownloadTest` and `DownloadResumeTest` assert against a real server. Here
/// the transfer belongs to a background `URLSession` — the thing that lets it continue while
/// the app is not running — and the bytes it holds are not reachable from this process. What
/// the system offers instead is `cancel(byProducingResumeData:)`, and this suite asserts the
/// three decisions the app makes around that token. The token itself is the system's, and
/// what a server answers a resumed request is not observable from a unit test: a background
/// session takes no `URLProtocol` stub.
@Suite("A held download carries on from what it fetched")
@MainActor
struct DownloadResumeTests {

    /// A store of its own, in a fresh defaults suite and an empty directory.
    private func store(holding downloads: [Download]) throws -> DownloadStore {
        let name = "download-resume-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        let store = DownloadStore(defaults: defaults, directory: directory)
        store.save(DownloadLibrary(downloads: downloads))
        return store
    }

    private func held(id: String = "one") -> Download {
        Download(
            id: id,
            title: "Harbour Lights 07",
            remote: URL(string: "https://example.invalid/hl07.epub")!,
            mediaType: "application/epub+zip",
            state: .paused(.waitingForWiFi),
            expectedBytes: 8_400_000,
            downloadedBytes: 4_000_000
        )
    }

    private func queue(_ store: DownloadStore) -> DownloadQueue {
        DownloadQueue(store: store, settings: { AppSettings(downloadOverWifiOnly: true) })
    }

    @Test("A held transfer's token is offered to the attempt that follows it")
    func theTokenIsOfferedBack() throws {
        let record = held()
        let store = try store(holding: [record])
        let queue = queue(store)
        let token = Data([9, 8, 7, 6])

        queue.keep(token, for: record.id)

        #expect(
            queue.resumption(for: record) == token,
            "A paused download's transfer starts over, because its token was not offered back."
        )
    }

    @Test("A download with nothing behind it asks the server for the whole file")
    func nothingHeldIsNoToken() throws {
        let record = held()
        let store = try store(holding: [record])
        let queue = queue(store)

        #expect(queue.resumption(for: record) == nil)
    }

    @Test("A token that arrives after the download is running again is not kept")
    func aLateTokenDoesNotDisplaceALiveTransfer() throws {
        // The system describes a stopped transfer some time after it is stopped, and Wi-Fi can
        // return inside that gap. The token then describes a transfer older than the one now
        // running, and keeping it would make the *next* attempt carry on from a position the
        // download has already passed.
        let record = held()
        let store = try store(holding: [record])
        // Wi-Fi-only off, or the pump this resume triggers holds the row again and the state
        // under test is never reached. The address resolves to nothing, so no transfer runs.
        let queue = DownloadQueue(store: store, settings: { AppSettings() })
        queue.resume(record.id)
        #expect(queue.library[record.id]?.state != .paused(.waitingForWiFi))

        queue.keep(Data([9, 8, 7, 6]), for: record.id)

        #expect(queue.resumption(for: record) == nil)
    }

    @Test("A download the reader cancelled keeps nothing to be resumed from")
    func aCancelledDownloadKeepsNothing() throws {
        // The order this guards is real: the reader cancels, the record and the directory go,
        // and the system describes the transfer it stopped some time afterwards. Writing that
        // token would re-create the folder the removal had just deleted, and leave a reader
        // paying for the makings of a download they cancelled.
        let record = held()
        let store = try store(holding: [record])
        let queue = queue(store)
        queue.remove(record.id)

        queue.keep(Data([9, 8, 7, 6]), for: record.id)

        #expect(queue.resumption(for: record) == nil)
        #expect(
            !FileManager.default.fileExists(
                atPath: store.resumeData(of: record).deletingLastPathComponent().path()
            ),
            "A cancelled download's folder was made again to hold a token nothing wants."
        )
    }
}
