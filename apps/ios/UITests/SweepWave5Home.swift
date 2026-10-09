import XCTest

/// Wave 5 frames of Home: the pale-cover hero and the two paths out of it.
///
/// Stateful on purpose. `testSetupPale` part-reads one pale comic, and the capture tests
/// that follow read that progress back from the device. Run the setup once, then the
/// captures in light and dark.
@MainActor
final class SweepWave5HomeTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func showHome(in app: XCUIApplication) throws {
        try w5Tab("Home", in: app)
        _ = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resume' OR label CONTAINS 'Pale'"))
            .firstMatch.waitForExistence(timeout: 15)
        hold(2)
    }

    func testSetupPale() throws {
        let app = sweepLaunch(grouping: "issues")
        try w5OpenPage(of: "Pale Morning", in: app)
        try readAndClose(turns: 1, in: app)
        backToShelf(in: app)
    }

    /// `one-library-three-destinations` 0b.1: byline and bar over the scrim of a pale cover.
    func testCapturePaleHero() throws {
        let app = sweepLaunch(sources: Wave5.twoCatalogues)
        try showHome(in: app)
        shutter(app, named: "home-hero-pale")
    }

    /// `publication-detail` 2.3, first path: a shelf card opens the publication page.
    func testCaptureShelfCardPath() throws {
        let app = sweepLaunch(sources: Wave5.twoCatalogues)
        try showHome(in: app)
        app.swipeUp()
        hold(1.5)
        let window = app.frame
        shutter(app, named: "home-shelf-card")
        let anchor = app.buttons["Broken Transfer"]
        XCTAssertTrue(anchor.waitForExistence(timeout: 5), "Home draws no Recently added shelf.")
        anchor.coordinate(withNormalizedOffset: CGVector(dx: 3.0, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: anchor.coordinate(withNormalizedOffset: CGVector(dx: -0.2, dy: 0.5)))
        hold(1.2)
        let card = try XCTUnwrap(
            app.buttons.allElementsBoundByIndex.first {
                let box = $0.frame
                return box.width > 100 && box.height > 150 && window.contains(box)
                    && !$0.label.hasPrefix("Pale") && !$0.label.hasPrefix("Broken")
                    && !$0.label.hasPrefix("Foreign")
            },
            "The shelf offered no second card. \(app.buttons.allElementsBoundByIndex.prefix(24).map { "\($0.label)|\($0.frame)" })"
        )
        card.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(
                format: "label BEGINSWITH 'Read' OR label BEGINSWITH 'Continue' OR label BEGINSWITH 'Download'"
            )).firstMatch.waitForExistence(timeout: 10),
            "The shelf card opened no publication page."
        )
        hold(1.5)
        shutter(app, named: "home-shelf-card-opens-page")
    }

    /// `publication-detail` 2.3, second path: the Keep reading hero opens the reader.
    func testCaptureHeroPath() throws {
        let app = sweepLaunch(sources: Wave5.twoCatalogues)
        try showHome(in: app)
        shutter(app, named: "home-hero")
        let hero = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pale Morning'")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 5), "Home has no hero for Pale Morning.")
        hero.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "The hero opened no reader.")
        hold(2)
        shutter(app, named: "home-hero-opens-reader")
    }

    // MARK: - Finish and Next in series (one-library-three-destinations 0b.3)

    func testSetupFinishNoNext() throws {
        let app = sweepLaunch(grouping: "issues")
        try w5OpenPage(of: "Fine Print", in: app)
        try readFast(turns: 2, in: app)
    }

    func testSetupFinishAndNext() throws {
        let app = sweepLaunch(grouping: "issues")
        try w5OpenPage(of: "Tidal Reach #1", in: app)
        try readToLastPage(in: app)
    }

    func testCaptureFinishNoNext() throws {
        let app = sweepLaunch()
        try showHome(in: app)
        shutter(app, named: "home-finish-no-next")
        XCTAssertTrue(app.buttons["Finish"].exists, "Home offers no Finish on a last page.")
        XCTAssertFalse(app.buttons["Next in series"].exists, "A comic with no next issue offers one.")
    }

    func testCaptureFinishAndNext() throws {
        let app = sweepLaunch()
        try showHome(in: app)
        shutter(app, named: "home-finish-and-next")
        XCTAssertTrue(app.buttons["Finish"].exists, "Home offers no Finish on a last page.")
        XCTAssertTrue(app.buttons["Next in series"].exists, "Home offers no Next in series.")
    }

    func testTapFinish() throws {
        let app = sweepLaunch()
        try showHome(in: app)
        app.buttons["Finish"].firstMatch.tap()
        hold(2)
    }

    func testCaptureAfterFinish() throws {
        let app = sweepLaunch()
        try showHome(in: app)
        shutter(app, named: "home-after-finish")
        app.swipeUp()
        app.swipeUp()
        hold(1.5)
        shutter(app, named: "home-finished-section")
    }
}
