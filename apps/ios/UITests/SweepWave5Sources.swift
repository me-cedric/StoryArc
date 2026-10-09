import XCTest

/// Wave 5 frames that need a catalogue: the three availability states of a publication
/// page, the browse surfaces that name no origin, and the stopped-source states.
///
/// Stateful and ordered. The mock catalogues serve `catalogue/` (Ashfall, Bellwether, Cinder,
/// Driftwood, Evergreen) and must be running for the first two tests and stopped for the
/// rest. See the frame sets' READMEs for the order.
@MainActor
final class SweepWave5SourcesTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private var primary: NSPredicate {
        NSPredicate(format: "label BEGINSWITH 'Read' OR label BEGINSWITH 'Continue' OR label BEGINSWITH 'Listen'")
    }

    private func launchWithSources(grouping: String = "series", layout: String = "grid",
                                   recents: String = "(\"Harbour\")") -> XCUIApplication {
        sweepLaunch(sources: Wave5.twoCatalogues, layout: layout, grouping: grouping,
                    recents: recents, pinDownloads: false)
    }

    private func dismissMenu(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.25)).tap()
        hold(0.8)
    }

    private func download(in app: XCUIApplication) throws {
        let button = try XCTUnwrap(app.buttons.matching(NSPredicate(format: "label == 'Download'")).firstMatch)
        button.tap()
        hold(6)
    }

    /// The on-device copy's page, reached through the Downloads destination.
    private func openCopy(_ title: String, in app: XCUIApplication) throws {
        try w5Tab("Downloads", in: app)
        hold(2)
        let cover = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10), "Downloads holds no copy of \(title).")
        cover.tap()
        XCTAssertTrue(app.buttons.matching(primary).firstMatch.waitForExistence(timeout: 10), "The copy opened no page.")
        hold(1.5)
    }

    /// `publication-detail` 2.1: the page of a catalogue title in its states. Servers up.
    /// Ashfall stays remote and answers: Download, and the library named. Driftwood is
    /// downloaded: Read, On this device, and the overflow before and after it is kept.
    func testCaptureAvailabilityStates() throws {
        try XCTSkipUnless(MockCatalogues.areRunning(), "The mock catalogues are not running.")
        let app = launchWithSources(grouping: "issues")
        try w5OpenPage(of: "Ashfall", in: app)
        app.swipeUp()
        hold(1.5)
        shutter(app, named: "page-remote-source-answering")
        backToShelf(in: app)
        try w5Tab("Downloads", in: app)
        hold(2)
        let held = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Driftwood'")).firstMatch.exists
        if !held {
            try w5OpenPage(of: "Driftwood", in: app)
            try download(in: app)
            backToShelf(in: app)
        }
        try openCopy("Driftwood", in: app)
        // A copy kept by an earlier run is un-kept first, so every run starts at "Download".
        try XCTUnwrap(hittable("More actions", in: app)).tap()
        hold(1)
        if let forget = app.buttons.matching(NSPredicate(format: "label == 'Remove download'")).firstMatch as XCUIElement?,
           forget.exists {
            forget.press(forDuration: 0.15)
            hold(2)
        } else {
            dismissMenu(in: app)
        }
        shutter(app, named: "page-downloaded")
        try XCTUnwrap(hittable("More actions", in: app)).tap()
        hold(1)
        shutter(app, named: "page-downloaded-overflow-offers-download")
        let keep = app.buttons.matching(NSPredicate(format: "label == 'Download'")).allElementsBoundByIndex
            .first { $0.isHittable && $0.frame.minY > 400 }
        try XCTUnwrap(keep, "The overflow offers no Download.").tap()
        hold(5)
        try XCTUnwrap(hittable("More actions", in: app)).tap()
        hold(1)
        shutter(app, named: "page-downloaded-overflow")
        XCTAssertTrue(app.descendants(matching: .any)["Remove download"].exists, "No Remove download after keeping.")
        dismissMenu(in: app)
    }

    /// `publication-detail` 2.1, third state: the same remote title with its library stopped.
    func testCaptureSourceStoppedPage() throws {
        try XCTSkipUnless(!MockCatalogues.areRunning(), "The mock catalogues are still running.")
        let app = launchWithSources(grouping: "issues")
        try w5OpenPage(of: "Ashfall", in: app)
        app.swipeUp()
        hold(2)
        shutter(app, named: "page-remote-source-stopped")
    }

    /// `one-library-three-destinations` 0b.2 and 3.3: a card whose library is away has no
    /// Resume button, and the four marks of the shelf. Servers stopped, Bellwether part-read
    /// with its copy deleted from disk.
    func testCaptureAwayHomeAndMarks() throws {
        try XCTSkipUnless(!MockCatalogues.areRunning(), "The mock catalogues are still running.")
        let app = sweepLaunch(sources: Wave5.twoCatalogues, sort: "lastRead", pinDownloads: false)
        try w5Tab("Home", in: app)
        hold(4)
        shutter(app, named: "home-card-library-away")
        try showTheShelf(in: app)
        waitForTheShelfToSettle(in: app, within: 15)
        hold(3)
        shutter(app, named: "library-four-marks")
        let labels = app.buttons.allElementsBoundByIndex.map(\.label).filter { $0.contains(", ") }
        XCTAssertFalse(labels.isEmpty)
        print("FOURMARKS " + labels.joined(separator: " | "))
    }

    /// `publication-detail` 3.4: browse surfaces name no origin, except Search.
    /// Servers up. Downloads one more title so Downloads holds a source-attributed copy.
    func testCaptureNoOriginOnBrowse() throws {
        try XCTSkipUnless(MockCatalogues.areRunning(), "The mock catalogues are not running.")
        let app = launchWithSources(grouping: "issues")
        try w5Tab("Downloads", in: app)
        hold(2)
        if !app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Cinder'")).firstMatch.exists {
            try w5OpenPage(of: "Cinder", in: app)
            try download(in: app)
            backToShelf(in: app)
        }
        try w5Tab("Home", in: app)
        hold(3)
        shutter(app, named: "no-origin-home")
        let list = launchWithSources(layout: "list")
        try showTheShelf(in: list)
        waitForTheShelfToSettle(in: list, within: 15)
        hold(3)
        shutter(list, named: "no-origin-library-list")
        try w5Tab("Downloads", in: list)
        hold(3)
        shutter(list, named: "no-origin-downloads")
        let search = launchWithSources(recents: "(\"Slow Transfer\")")
        try w5Tab("Search", in: search)
        try XCTUnwrap(hittable("Slow Transfer", in: search, timeout: 8)).tap()
        XCTAssertTrue(
            search.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", MockCatalogues.attic))
                .firstMatch.waitForExistence(timeout: 15),
            "Search rows do not name the library."
        )
        hold(2)
        shutter(search, named: "origin-named-in-search")
    }
}
