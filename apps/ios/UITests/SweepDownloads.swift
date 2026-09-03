import XCTest

/// The Downloads destination: the shelf, the queue above it, and the confirmation.
///
/// `ScreenshotTests.testCaptureDownloads` photographs this destination with no transfer in
/// flight, which is the state it is in on every device nobody has arranged — and
/// `offline-downloads` spends most of its words on the state that is therefore never
/// photographed. The queue "listing active, queued and failed items with per-item and global
/// pause, resume, cancel and reorder" has no picture anywhere in this repository.
///
/// **The record is injected, not fetched.** A transfer photographed by starting a real one
/// needs a server, a network, and a file large enough to still be arriving when the shutter
/// falls — three things that make a capture flaky rather than repeatable. `DownloadStore`
/// keeps its record in `UserDefaults`, and the argument domain outranks the standard one, so
/// a launch argument hands this screen a queue for one launch and leaves nothing behind. The
/// same mechanism `ScreenshotTests` uses for `-app.storyarc.whatsNewSeen`.
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
    /// *queued* row carries, and a failure sitting in the same list as a success.
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
    /// nothing has photographed it.
    func testCaptureDownloadQueueAtLargestText() throws {
        let app = sweepLaunch(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            downloads: Self.queue
        )
        try showQueue(in: app)
        hold(1)
        shutter(app, named: "downloads-queue-ax5")
    }

    /// Stopping one: the confirmation, which names the title and what it will free.
    func testCaptureDownloadStopConfirmation() throws {
        let app = sweepLaunch(downloads: Self.queue)
        try showQueue(in: app)
        try XCTUnwrap(hittable("Stop", in: app), "A queued row offers no Stop.").tap()
        XCTAssertTrue(
            app.staticTexts["Remove this download?"].waitForExistence(timeout: 5),
            "Stop asked for no confirmation. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(15).map(\.label))"
        )
        hold(0.5)
        shutter(app, named: "downloads-stop-confirm")
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
    private func showQueue(in app: XCUIApplication) throws {
        try showDownloads(in: app)
        XCTAssertTrue(
            app.staticTexts["Coming down now"].waitForExistence(timeout: 10),
            "No transfer queue on this screen — the injected download record was not read."
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
