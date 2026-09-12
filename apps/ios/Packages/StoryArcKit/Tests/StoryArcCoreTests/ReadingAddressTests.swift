import Foundation
import Testing

@testable import StoryArcCore

/// `offline-downloads`' *Reading while downloading*, asserted case for case.
///
/// > **WHEN** a user opens a publication that is still downloading
/// > **THEN** it opens immediately by streaming, and switches to the local copy when the
/// > download completes, without interrupting reading
///
/// Before this rule existed both platforms waited for the whole file: the publication's page
/// offered a download and nothing else while a transfer of the same book was running.
///
/// Android's `ReadingAddressTest` asserts the same cases.
@Suite("Reading while downloading")
struct ReadingAddressTests {
    private let remote = URL(string: "https://books.example/comic.cbz")!
    private let onDisk = URL(fileURLWithPath: "/data/downloads/urn-storyarc-6/Fine Print.cbz")

    private func transfer(
        _ state: Download.State,
        remote: URL? = nil,
        id: String = "urn:storyarc:6"
    ) -> Download {
        Download(
            id: id,
            title: "Fine Print",
            remote: remote ?? self.remote,
            mediaType: "application/vnd.comicbook+zip",
            state: state
        )
    }

    @Test("a running transfer is read from the address it is fetching")
    func runningStreams() {
        #expect(
            ReadingAddress.of(
                local: nil,
                transfer: transfer(.running),
                readsWhereItLies: true
            ) == remote
        )
    }

    @Test("a queued transfer is read the same way, before a byte has moved")
    func queuedStreams() {
        // "Opens immediately" is immediate: a reader who presses Read on a publication that
        // is fifth in the queue does not wait for the four ahead of it.
        #expect(
            ReadingAddress.of(
                local: nil,
                transfer: transfer(.queued),
                readsWhereItLies: true
            ) == remote
        )
    }

    @Test("a transfer held for Wi-Fi is still readable")
    func heldStreams() {
        // The bytes are on the server whether or not the app is spending mobile data on a
        // copy of them, and a held transfer resumes rather than ends.
        #expect(
            ReadingAddress.of(
                local: nil,
                transfer: transfer(.paused(.waitingForWiFi)),
                readsWhereItLies: true
            ) == remote
        )
    }

    @Test("a copy on the device wins over the transfer that brought it")
    func localWins() {
        #expect(
            ReadingAddress.of(
                local: onDisk,
                transfer: transfer(.running),
                readsWhereItLies: true
            ) == onDisk
        )
    }

    @Test("a failed transfer offers no address, so its retry action is what the reader sees")
    func failedOffersNothing() {
        #expect(
            ReadingAddress.of(
                local: nil,
                transfer: transfer(.failed(reason: "the server refused", attempts: 3)),
                readsWhereItLies: true
            ) == nil
        )
    }

    @Test("a finished transfer with no file left offers no address")
    func finishedWithoutFileOffersNothing() {
        #expect(
            ReadingAddress.of(
                local: nil,
                transfer: transfer(.finished),
                readsWhereItLies: true
            ) == nil
        )
    }

    @Test("a decoder that wants a file of its own is never sent an address")
    func decoderWantingAFile() {
        #expect(
            ReadingAddress.of(
                local: nil,
                transfer: transfer(.running),
                readsWhereItLies: false
            ) == nil
        )
    }

    @Test("an address no ranged reader is registered for is never streamed")
    func unknownScheme() {
        // The defect this prevents: a path handed to the opener under a scheme it has no
        // reader for is opened as a local file, and a local file at `ftp://…` is not there.
        #expect(
            ReadingAddress.of(
                local: nil,
                transfer: transfer(.running, remote: URL(string: "ftp://books.example/c.cbz")!),
                readsWhereItLies: true
            ) == nil
        )
    }

    @Test("no transfer and no copy is nothing to open")
    func nothingToOpen() {
        #expect(ReadingAddress.of(local: nil, transfer: nil, readsWhereItLies: true) == nil)
    }

    @Test("the copy that arrives for a streamed address is the one fetching it")
    func arrivedMatchesTheAddress() {
        let mine = transfer(.finished)
        let other = transfer(
            .finished,
            remote: URL(string: "https://books.example/other.cbz")!,
            id: "urn:storyarc:7"
        )
        let arrived = ReadingAddress.arrived(
            at: remote,
            in: DownloadLibrary(downloads: [other, mine])
        )
        #expect(arrived == mine)
    }

    @Test("a transfer still running has not arrived")
    func stillRunningHasNotArrived() {
        #expect(
            ReadingAddress.arrived(
                at: remote,
                in: DownloadLibrary(downloads: [transfer(.running)])
            ) == nil
        )
    }

    @Test("a reader already on a local file has nothing to switch to")
    func localReaderSwitchesToNothing() {
        #expect(
            ReadingAddress.arrived(
                at: onDisk,
                in: DownloadLibrary(downloads: [transfer(.finished)])
            ) == nil
        )
    }
}
