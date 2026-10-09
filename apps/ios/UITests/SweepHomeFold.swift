import XCTest

/// Home with a publication in progress, photographed for the fold.
///
/// `home-screen`: on a phone at the default text size "the next section's heading is visible
/// without scrolling". The hero exists only when something is in progress, and a seeded device
/// has nothing in progress, so `SweepHomeTests` never photographed it. This turns one page of a
/// comic, closes it, and goes Home (task 0b.4).
@MainActor
final class SweepHomeFoldTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCaptureHomeFold() throws {
        try captureHome(named: "home-fold")
    }

    private func captureHome(named name: String) throws {
        // The position is stored, so the relaunch below finds the comic in progress.
        let reading = sweepLaunch()
        try readAComic(named: "Fine Print", in: reading)
        reading.terminate()

        let app = sweepLaunch()
        try XCTUnwrap(destination("Home", in: app), "The shell offers no Home tab.").tap()
        XCTAssertTrue(app.staticTexts["Home"].waitForExistence(timeout: 10))
        hold(2)
        shutter(app, named: name)
    }

    /// Opens one comic from the shelf, turns a page so it counts as started, and closes it.
    private func readAComic(named title: String, in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        var cover = wanted.allElementsBoundByIndex.first(where: \.isHittable)
        for _ in 0..<8 where cover == nil {
            app.swipeUp()
            cover = wanted.allElementsBoundByIndex.first(where: \.isHittable)
        }
        try XCTSkipUnless(cover != nil, "This device's shelf never showed a cover for “\(title)”.")
        cover?.tap()

        let open = app.buttons.matching(opensAPublication).firstMatch
        try XCTSkipUnless(open.waitForExistence(timeout: 20), "“\(title)”'s page offered no way to open it.")
        var action = app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable)
        for _ in 0..<4 where action == nil {
            app.swipeUp()
            action = app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable)
        }
        try XCTUnwrap(action, "“\(title)”'s page offered no hittable way to open it.").tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "Opening “\(title)” reached no reader.")
        hold(2)

        // One turn, on the trailing edge: the centre is the chrome toggle.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        hold(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "A centre tap revealed no Close button.")
        close.tap()
        hold(1)
    }
}
