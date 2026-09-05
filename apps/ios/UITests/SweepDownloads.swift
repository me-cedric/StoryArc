import XCTest

/// The Downloads destination: the shelf, the queue above it, and the confirmations.
///
/// `ScreenshotTests.testCaptureDownloads` photographs this destination with no transfer in
/// flight, which is the state it is in on every device nobody has arranged — and
/// `offline-downloads` spends most of its words on the state that is therefore never
/// photographed. The queue "listing active, queued and failed items with per-item and global
/// pause, resume, cancel and reorder" had no picture anywhere in this repository until the
/// September sweep.
///
/// **The record is injected, not fetched.** A transfer photographed by starting a real one
/// needs a server, a network, and a file large enough to still be arriving when the shutter
/// falls — three things that make a capture flaky rather than repeatable. `DownloadStore`
/// keeps its record in `UserDefaults`, and the argument domain outranks the standard one, so
/// a launch argument hands this screen a queue for one launch and leaves nothing behind. The
/// same mechanism `ScreenshotTests` uses for `-app.storyarc.whatsNewSeen`.
///
/// **The walks here open confirmations and never confirm them, and tap nothing that writes.**
/// A tap on *Retry* or a confirmed *Remove* would write the standard domain, and the next
/// ordinary launch on this simulator would show a transfer of *The Peregrine* from
/// `example.invalid` that nobody queued. What *Retry* does is proved on the host, in
/// `DownloadQueueRetryTests`; what it looks like is the queued row two rows above it.
///
/// What the injection cannot reach is stated rather than faked: `StoredDownload` encodes
/// `finished`, `failed` and everything else as `queued`, so *running* and *paused* are not
/// states this file can produce. `downloads.paused.waitingForWiFi` and its two siblings have
/// no picture here and the README says so.
@MainActor
final class SweepDownloadsTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The destination with nothing in flight: the readable shelf and what it weighs.
    func testCaptureDownloadsShelf() throws {
        let app = sweepLaunch()
        try showDownloads(in: app)
        hold(2)
        shutter(app, named: "downloads-shelf")
    }

    /// The same at the largest accessibility text size, where the grid drops a column.
    func testCaptureDownloadsShelfAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try showDownloads(in: app)
        hold(2)
        shutter(app, named: "downloads-shelf-ax5")
    }

    /// The queue: one part-way through, one waiting behind it, and one that gave up.
    ///
    /// Three rows because one row cannot show what the section is for. A single transfer
    /// looks like a progress bar; three show the order, the reorder controls that only a
    /// *queued* row carries, and a failure sitting in the same list as a success — with the
    /// two controls only a failed row carries, *Retry* and *Remove download*, where the other
    /// two rows carry *Stop*.
    func testCaptureDownloadQueue() throws {
        let app = sweepLaunch(downloads: Self.queue)
        try showQueue(in: app)
        hold(1)
        shutter(app, named: "downloads-queue")
    }

    /// The queue at the largest accessibility text size, where a row becomes two lines.
    ///
    /// `DownloadQueueRow` branches on `dynamicTypeSize.isAccessibilitySize` because "the title
    /// truncates to two characters while *Stop* wraps to two lines". This is the branch, and
    /// nothing had photographed it. The failed row's two buttons stop sharing a line here too.
    func testCaptureDownloadQueueAtLargestText() throws {
        let app = sweepLaunch(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            downloads: Self.queue
        )
        try showQueue(in: app)
        hold(1)
        shutter(app, named: "downloads-queue-ax5")
    }

    /// The failed row at the largest accessibility text size, scrolled into the frame.
    ///
    /// At this size one row fills the screen, so the third row — the failed one — begins a
    /// screen and a half below the heading and `testCaptureDownloadQueueAtLargestText`
    /// photographs two Stops and no Retry. This walks down to it. The two buttons stop
    /// sharing a line here: the pair goes one under the other, and neither label truncates.
    func testCaptureFailedRowAtLargestText() throws {
        let app = sweepLaunch(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            downloads: Self.queue
        )
        try showQueue(in: app)
        try scrollToFailedRow(in: app, remove: "Remove download")
        hold(1)
        shutter(app, named: "downloads-failed-ax5")
    }

    /// The same, in German, which is the longest of the four languages on this row.
    ///
    /// *Download entfernen* on its own is wider than the row at this size, so the label has
    /// to wrap rather than truncate — a frame in English would not show whether it does.
    func testCaptureFailedRowAtLargestTextInGerman() throws {
        let app = sweepLaunch(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            downloads: Self.queue,
            language: "de"
        )
        try showQueue(in: app, heading: "Kommt gerade an")
        try scrollToFailedRow(in: app, remove: "Download entfernen")
        hold(1)
        shutter(app, named: "downloads-failed-ax5-de")
    }

    /// Stopping one: the confirmation, which is about a transfer rather than about a file.
    ///
    /// **This assertion is the defect, pinned.** It read `Remove this download?` until
    /// 2026-09-04, and passed, because *Stop* on a row still arriving put up the words for
    /// deleting a finished download — "This deletes the copy of Harbour Lights 03 on this
    /// device. Your reading position is kept" — over a publication with no copy on the
    /// device and no reading position. The frame it took is
    /// `docs/designs/screenshots/ios-sweep-2026-09-02/ios-downloads-stop-confirm.png`.
    func testCaptureDownloadStopConfirmation() throws {
        let app = sweepLaunch(downloads: Self.queue)
        try showQueue(in: app)
        try XCTUnwrap(hittable("Stop", in: app), "A queued row offers no Stop.").tap()
        XCTAssertTrue(
            app.staticTexts["Stop this download?"].waitForExistence(timeout: 5),
            "Stop asked for no confirmation, or asked the removal's question. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(15).map(\.label))"
        )
        XCTAssertFalse(
            app.staticTexts["Remove this download?"].exists,
            "Stopping a transfer is still confirmed with the words for deleting a download."
        )
        hold(0.5)
        shutter(app, named: "downloads-stop-confirm")
    }

    /// Removing the one that gave up: the row's controls, and the confirmation that promises
    /// neither a copy nor a stop.
    ///
    /// **The second defect, pinned.** Until 2026-09-05 the failed row's only control was
    /// *Stop*, under a line reading "Failed after 3 attempts" — a transfer that had already
    /// stopped, offered a stop and no retry, when `offline-downloads` asks a failed download
    /// for "a plain-language reason and a retry action". Android fixed its row the same day.
    /// The row offers *Retry* first and *Remove download* beside it now, and the other two
    /// rows still offer *Stop*: two Stops on this screen, not three.
    ///
    /// Removing it is a fourth question. "This stops the transfer" is as untrue of a failed
    /// download as the removal sentence is of a running one, so the confirmation says what a
    /// reader gets back — nothing, because nothing arrived.
    func testCaptureDownloadDiscardConfirmation() throws {
        let app = sweepLaunch(downloads: Self.queue)
        try showQueue(in: app)

        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label == %@", "Retry")).count, 1,
            "The failed row offers no Retry, or a row that did not fail offers one."
        )
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label == %@", "Stop")).count, 2,
            "A failed transfer is still offered a Stop it cannot stop, or a moving one lost its Stop."
        )

        try XCTUnwrap(hittable("Remove download", in: app), "The failed row offers no Remove.").tap()
        XCTAssertTrue(
            app.staticTexts["Remove this download?"].waitForExistence(timeout: 5),
            "Remove asked for no confirmation, or asked the stop's question. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(15).map(\.label))"
        )
        XCTAssertTrue(
            app.staticTexts[
                "Nothing of The Peregrine reached this device. It leaves the queue, and it can be downloaded again."
            ].exists,
            "Removing a failed transfer is confirmed with a sentence about a copy, or about a stop."
        )
        XCTAssertFalse(
            app.staticTexts["Stop this download?"].exists,
            "Removing a transfer that already stopped is still confirmed as a stop."
        )
        hold(0.5)
        shutter(app, named: "downloads-discard-confirm")
    }

    /// The Downloads destination while a book is being spoken, so the docked transport is in
    /// the frame with the tab bar rather than beside it on the shelf.
    ///
    /// `PlayerScreenshotTests` photographs the compact bar over the library. This is the same
    /// bar over the one destination whose own content also runs to the bottom edge — a shelf
    /// *and* a queue *and* a total, all insetting against the same accessory.
    func testCaptureDownloadsWithPlayer() throws {
        let app = sweepLaunch()
        try openAnAudiobook(in: app)
        try XCTUnwrap(destination("Downloads", in: app), "no Downloads tab").tap()
        hold(2)
        shutter(app, named: "downloads-with-player")
    }

    // MARK: - The walk

    private func showDownloads(in app: XCUIApplication) throws {
        try XCTUnwrap(destination("Downloads", in: app), "The shell offers no Downloads tab.").tap()
        XCTAssertTrue(
            app.staticTexts["Downloads"].waitForExistence(timeout: 10),
            "Tapping Downloads did not open a screen headed Downloads."
        )
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
    }

    /// Downloads, with the queue actually on it.
    ///
    /// The heading is the landmark, and it has to be: this destination draws a shelf whether
    /// or not the injection took, so a walk that waited on the scroll view would photograph a
    /// perfectly ordinary Downloads screen under a filename saying *queue*. That is the exact
    /// failure `AuditWalk.swift` argues about, arriving through a launch argument.
    ///
    /// The heading is `downloads.inFlight` in whichever language the launch chose; the tab
    /// and the screen's title are *Downloads* in German as in English, so only this one
    /// changes.
    private func showQueue(in app: XCUIApplication, heading: String = "Coming down now") throws {
        try showDownloads(in: app)
        XCTAssertTrue(
            app.staticTexts[heading].waitForExistence(timeout: 10),
            "No transfer queue on this screen — the injected download record was not read."
        )
    }

    /// Scrolls the queue until the failed row's second control is on screen.
    ///
    /// The *Remove* button rather than the title, because the controls sit under the title
    /// and a title at the foot of the screen has its buttons below the fold. Named per
    /// language, because the label is the one thing on this row that is translated. Swiped
    /// slowly, so a swipe does not carry the row past the top of the screen — the loop
    /// only ever moves down.
    private func scrollToFailedRow(in app: XCUIApplication, remove: String) throws {
        let wanted = app.buttons.matching(NSPredicate(format: "label == %@", remove))
        for _ in 0..<8 where wanted.allElementsBoundByIndex.first(where: \.isHittable) == nil {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertNotNil(
            wanted.allElementsBoundByIndex.first(where: \.isHittable),
            "The failed row's \(remove) never came on screen. On screen: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(12).map(\.label))"
        )
    }

    /// Three transfers: one part-way, one waiting, one failed after three attempts.
    ///
    /// `StoredDownload`'s own shape, written out because the UI-test bundle cannot see
    /// `Persistence`. `DownloadStoreTests` pins the encoding on the host side; if this drifts
    /// from it, `showQueue` fails by name rather than photographing a shelf.
    private static let queue = """
    [{"id":"sweep-1","title":"Harbour Lights 03","remote":"https://example.invalid/hl03.epub",\
    "mediaType":"application/epub+zip","expectedBytes":8400000,"downloadedBytes":3100000,\
    "isFinished":false,"attempts":0,"verificationFailures":0},\
    {"id":"sweep-2","title":"Tidal Reach 04","remote":"https://example.invalid/tr04.cbz",\
    "mediaType":"application/vnd.comicbook+zip","expectedBytes":41000000,"downloadedBytes":0,\
    "isFinished":false,"attempts":0,"verificationFailures":0},\
    {"id":"sweep-3","title":"The Peregrine","remote":"https://example.invalid/pg.epub",\
    "mediaType":"application/epub+zip","expectedBytes":2200000,"downloadedBytes":190000,\
    "isFinished":false,"failure":"The server did not answer in time.","attempts":3,\
    "verificationFailures":0}]
    """
}
