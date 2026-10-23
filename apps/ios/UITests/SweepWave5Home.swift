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

    /// The Continue reading section, which exists only with a hero to show. The hero's own
    /// Resume, Finish and Next are hidden from the accessibility tree (task 28.10), so the
    /// walks wait for the section heading and find the card by its title.
    private func showHome(in app: XCUIApplication) throws {
        try w5Tab("Home", in: app)
        _ = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continue reading'"))
            .firstMatch.waitForExistence(timeout: 15)
        hold(2)
    }

    /// The hero card of one title: one element, labelled title, byline, kicker and what is left.
    /// Its height tells it from the same title's cover on a shelf below.
    private func hero(_ title: String, in app: XCUIApplication) -> XCUIElement? {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
            .allElementsBoundByIndex.first { $0.frame.height > 200 }
    }

    /// Finish sits at the foot of the card's caption, 16 pt in from the left and bottom edges.
    /// The button is not in the tree, so the tap lands by position on the card that is.
    private func tapFinish(on card: XCUIElement) {
        let box = card.frame
        card.coordinate(withNormalizedOffset: CGVector(dx: 56 / box.width, dy: 1 - 33 / box.height)).tap()
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
            "The shelf offered no second card. "
                + "\(app.buttons.allElementsBoundByIndex.prefix(24).map { "\($0.label)|\($0.frame)" })"
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

    /// The frame shows Finish without Next in series; the tree says only that the card is up.
    func testCaptureFinishNoNext() throws {
        let app = sweepLaunch()
        try showHome(in: app)
        shutter(app, named: "home-finish-no-next")
        XCTAssertNotNil(hero("Fine Print", in: app), "Home offers no card for the comic on its last page.")
    }

    /// The frame shows Finish beside Next in series; the tree says only that the card is up.
    func testCaptureFinishAndNext() throws {
        let app = sweepLaunch()
        try showHome(in: app)
        shutter(app, named: "home-finish-and-next")
        XCTAssertNotNil(hero("Tidal Reach", in: app), "Home offers no card for the issue on its last page.")
    }

    func testTapFinish() throws {
        let app = sweepLaunch()
        try showHome(in: app)
        let card = try XCTUnwrap(hero("Fine Print", in: app), "Home offers no card for the comic on its last page.")
        tapFinish(on: card)
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
