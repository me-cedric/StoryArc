import Foundation
import Testing

@testable import StoryArcCore

/// The connection half of `offline-downloads`' *Wi-Fi only*, as a pure rule.
///
/// "When the 'download over Wi-Fi only' setting is on and the device is on cellular, downloads
/// pause and state that they are waiting for Wi-Fi, and resume automatically when it returns."
/// The queue only started transfers, so a reader who began a download on Wi-Fi and walked out
/// of range kept downloading over cellular: the setting protected the queue and not the
/// transfer already running.
///
/// One pass answers both halves, so a connection that drops and returns cannot pause and
/// resume the same row twice in one call. Android's `DownloadWifiHoldTest` asserts the same
/// cases.
@Suite("A metered connection holds what it does not permit, and puts back what it does")
struct DownloadWifiHoldTests {
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
            download("space", state: .paused(.outOfSpace)),
            download("failed", state: .failed(reason: "the server refused", attempts: 2)),
            download("finished", state: .finished),
        ])
    }

    @Test("A running transfer the connection forbids is paused, and says why")
    func runningIsPaused() {
        let held = mixed.reconsideringWifi { _ in false }

        #expect(held["running"]?.state == .paused(.waitingForWiFi))
        #expect(held["queued"]?.state == .paused(.waitingForWiFi))
    }

    @Test("A download the reader paused keeps their reason")
    func readerPauseSurvives() {
        let held = mixed.reconsideringWifi { _ in false }

        #expect(held["reader"]?.state == .paused(.byReader))
        #expect(held["space"]?.state == .paused(.outOfSpace))
        #expect(held["failed"]?.state == .failed(reason: "the server refused", attempts: 2))
        #expect(held["finished"]?.state == .finished)
    }

    @Test("Nothing is dropped and no fetched byte is forgotten")
    func bytesSurvive() {
        var partial = download("running", state: .running)
        partial.downloadedBytes = 4_000_000
        partial.expectedBytes = 8_400_000
        let held = DownloadLibrary(downloads: [partial]).reconsideringWifi { _ in false }

        // Pausing is not cancelling: the record stays and the bytes counted against it stay
        // with it. `offline-downloads` resumes a held download rather than starting a new one.
        #expect(held.downloads.count == 1)
        #expect(held["running"]?.downloadedBytes == 4_000_000)
        #expect(held["running"]?.expectedBytes == 8_400_000)
    }

    @Test("A download the connection permits is put back in the queue")
    func wifiReturnsPutsBack() {
        let released = mixed.reconsideringWifi { _ in false }.reconsideringWifi { _ in true }

        #expect(released["queued"]?.state == .queued)
        #expect(released["running"]?.state == .queued)
        #expect(released["reader"]?.state == .paused(.byReader))
        #expect(released["space"]?.state == .paused(.outOfSpace))
    }

    @Test("A permitted download is not paused while a forbidden one is")
    func grantedRunsWhileTheRestWaits() {
        // `offline-downloads` grants the metered override "for that item only". The grant
        // decides one row and must not decide the row beside it.
        let held = mixed.reconsideringWifi { $0.id == "running" }

        #expect(held["running"]?.state == .running)
        #expect(held["queued"]?.state == .paused(.waitingForWiFi))
    }

    @Test("A connection that changes nothing writes nothing")
    func nothingToDoIsNoChange() {
        // The anti-thrash guarantee the queue depends on: a pass that alters no row returns
        // the same value, so the caller can compare and skip the write to the store.
        #expect(mixed.reconsideringWifi { _ in true } == mixed)
        let once = mixed.reconsideringWifi { _ in false }
        #expect(once.reconsideringWifi { _ in false } == once)
    }
}

/// What a screen with no queue is told the queue is waiting for.
///
/// `offline-downloads` requires a held queue to say what it is waiting for, and the three
/// situations have three different remedies. The rule reads the records the queue wrote,
/// which is what lets a settings screen answer without holding a queue at all.
@Suite("A held queue names one reason")
struct DownloadHoldTests {
    private func download(_ id: String, state: Download.State, bytes: Int64 = 0) -> Download {
        Download(
            id: id,
            title: id,
            remote: URL(filePath: "/nowhere/\(id).cbz"),
            mediaType: "application/vnd.comicbook+zip",
            state: state,
            downloadedBytes: bytes
        )
    }

    @Test("A queue with nothing waiting is not held")
    func idleIsNotHeld() {
        let library = DownloadLibrary(downloads: [download("finished", state: .finished, bytes: 9)])
        #expect(library.hold(limit: nil) == nil)
        // The limit is reached and there is nothing to hold. A screen that announced a hold
        // here would be reporting a queue that is not waiting for anything.
        #expect(library.hold(limit: 1) == nil)
    }

    @Test("A download waiting for Wi-Fi holds the queue")
    func wifiHolds() {
        let library = DownloadLibrary(downloads: [
            download("one", state: .paused(.waitingForWiFi)),
        ])
        #expect(library.hold(limit: nil) == .waitingForWifi)
    }

    @Test("The device's own shortage is named before anything the reader chose")
    func shortageComesFirst() {
        let library = DownloadLibrary(downloads: [
            download("one", state: .paused(.waitingForWiFi)),
            download("two", state: .paused(.outOfSpace)),
        ])
        #expect(library.hold(limit: nil) == .outOfSpace)
    }

    @Test("The reader's own maximum holds a queue that still has work")
    func limitHolds() {
        let library = DownloadLibrary(downloads: [
            download("kept", state: .finished, bytes: 2_000),
            download("wanted", state: .queued),
        ])
        #expect(library.hold(limit: 1_000) == .storageFull)
        #expect(library.isAtLimit(1_000))
        #expect(library.hold(limit: 3_000) == nil)
        #expect(!library.isAtLimit(3_000))
    }

    @Test("A download the reader paused is not a reason the queue is held")
    func readerPauseIsNotAHold() {
        // The reader stopped it. A screen saying the queue is waiting for something would be
        // telling them to fix a condition they created and can undo on the row itself.
        let library = DownloadLibrary(downloads: [download("one", state: .paused(.byReader))])
        #expect(library.hold(limit: nil) == nil)
    }
}
