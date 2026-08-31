import Foundation
import Testing

@testable import StoryArcCore

/// `offline-downloads`' *Device storage is low*, asserted case for case. Android's
/// `StorageHeadroomTest` asserts the same cases, which is how the two queues stay honest
/// about the one question that decides whether the app fills a reader's phone.
@Suite("Storage headroom decides whether the queue may write")
struct StorageHeadroomTests {
    private let reserve = StorageHeadroom.reserveBytes

    @Test("A volume with room to spare is not low")
    func plentyIsNotLow() {
        #expect(!StorageHeadroom.isLow(free: reserve * 4))
        #expect(StorageHeadroom.hasRoom(free: reserve * 4))
    }

    @Test("A volume below the reserve is low even with nothing incoming")
    func belowTheFloorIsLow() {
        #expect(StorageHeadroom.isLow(free: reserve - 1))
        #expect(!StorageHeadroom.hasRoom(free: reserve - 1))
    }

    @Test("Exactly the reserve is room enough")
    func theFloorItselfIsRoom() {
        #expect(!StorageHeadroom.isLow(free: reserve))
    }

    @Test("An incoming file that would eat into the reserve is refused")
    func incomingCountsAgainstTheFloor() {
        // Twice the floor free, and a download that would leave one byte less than the
        // floor behind. The queue has to refuse it before it starts, not after.
        #expect(StorageHeadroom.isLow(free: reserve * 2, incoming: reserve + 1))
        #expect(!StorageHeadroom.isLow(free: reserve * 2, incoming: reserve))
    }

    @Test("An unknown free space does not stop the queue")
    func unknownFreeSpaceIsNotAFailure() {
        // AGENTS.md §2: offline is a normal state, not an error — and a volume that
        // declines to report is not a full one. Refusing every download for want of a
        // number would be an invented failure the reader could never clear.
        #expect(!StorageHeadroom.isLow(free: nil))
        #expect(!StorageHeadroom.isLow(free: nil, incoming: reserve * 100))
        #expect(StorageHeadroom.hasRoom(free: nil))
    }

    @Test("An unknown incoming size still has to clear the floor")
    func unknownIncomingStillChecksTheFloor() {
        // The usual case: an OPDS feed states no length, so the queue knows the volume and
        // not the file. The floor is the half of the rule it can still enforce.
        #expect(StorageHeadroom.isLow(free: reserve - 1, incoming: nil))
        #expect(!StorageHeadroom.isLow(free: reserve + 1, incoming: nil))
    }

    @Test("Nonsense numbers cannot make room appear")
    func negativesAreClamped() {
        #expect(StorageHeadroom.isLow(free: -1))
        // A negative size would otherwise be subtracted as an addition.
        #expect(StorageHeadroom.isLow(free: reserve - 1, incoming: -reserve))
    }
}

/// The two library operations the shortage drives, which decide what a reader sees on
/// every row of the downloads screen. Android's `DownloadLibraryTest` asserts the same
/// cases.
@Suite("A shortage pauses what is pending and leaves the rest alone")
struct DownloadSpaceHoldTests {
    private func download(_ id: String, state: Download.State) -> Download {
        Download(
            id: id,
            title: id,
            remote: URL(filePath: "/nowhere/\(id).cbz"),
            mediaType: "application/vnd.comicbook+zip",
            state: state
        )
    }

    private var mixed: DownloadLibrary {
        DownloadLibrary(downloads: [
            download("queued", state: .queued),
            download("running", state: .running),
            download("reader", state: .paused(.byReader)),
            download("failed", state: .failed(reason: "the server refused", attempts: 2)),
            download("finished", state: .finished),
        ])
    }

    @Test("Queued and running are paused, and say why")
    func pendingIsPaused() {
        let held = mixed.pausingForSpace()

        #expect(held["queued"]?.state == .paused(.outOfSpace))
        #expect(held["running"]?.state == .paused(.outOfSpace))
    }

    @Test("A download the reader paused is not re-labelled")
    func readerPauseSurvives() {
        // The reason on the row is the reader's own, and overwriting it would resume their
        // download the moment space returned — which is not what they asked for.
        #expect(mixed.pausingForSpace()["reader"]?.state == .paused(.byReader))
    }

    @Test("Nothing is deleted, and a finished download keeps its state")
    func nothingIsDeleted() {
        let held = mixed.pausingForSpace()

        // `offline-downloads`: "never deletes a download without asking".
        #expect(held.downloads.count == mixed.downloads.count)
        #expect(held["finished"]?.state == .finished)
        #expect(held["failed"]?.state == .failed(reason: "the server refused", attempts: 2))
    }

    @Test("Room returning puts back only what the shortage held")
    func roomReturnsOnlyItsOwn() {
        let released = mixed.pausingForSpace().resumingAfterSpace()

        #expect(released["queued"]?.state == .queued)
        #expect(released["running"]?.state == .queued)
        #expect(released["reader"]?.state == .paused(.byReader))
        #expect(released["failed"]?.state == .failed(reason: "the server refused", attempts: 2))
        #expect(released["finished"]?.state == .finished)
    }

    @Test("Releasing a library that was never held changes nothing")
    func releaseIsIdempotent() {
        #expect(mixed.resumingAfterSpace() == mixed)
    }
}
