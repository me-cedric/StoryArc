import XCTest

/// Home, and the two surfaces it is the only way into: *see all* and Shelves.
///
/// `ScreenshotTests.testCaptureHome` takes the top of this screen and nothing else. Home is
/// four stacked sections with a hero at the head of it — none of the lower three has ever been
/// photographed, and the shelves screen behind the link at its foot has no picture at all
/// despite being where `collections-and-reading-lists` lives.
@MainActor
final class SweepHomeTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The top of Home: the hero, and whatever section follows it.
    func testCaptureHomeTop() throws {
        let app = sweepLaunch()
        try showHome(in: app)
        hold(2)
        shutter(app, named: "home-top")
    }

    /// The top of Home at the largest accessibility text size, where the hero's own caption
    /// and the section headings each grow and the hero does not.
    func testCaptureHomeTopAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try showHome(in: app)
        hold(2)
        shutter(app, named: "home-top-ax5")
    }

    /// Home scrolled down: the rows under the hero, and the link to Shelves at the foot.
    func testCaptureHomeLower() throws {
        let app = sweepLaunch()
        try showHome(in: app)
        hold(2)
        for _ in 0..<3 { app.swipeUp() }
        hold(1.5)
        shutter(app, named: "home-lower")
    }

    /// Home at its end, which is the only place the floating tab bar's question can be
    /// answered on this destination: is a caption *passing under* the bar, or stuck behind it?
    func testCaptureHomeEnd() throws {
        let app = sweepLaunch()
        try showHome(in: app)
        hold(2)
        for _ in 0..<8 { app.swipeUp() }
        hold(1.5)
        shutter(app, named: "home-end")
    }

    /// A *see all* grid, which is a whole screen reachable only from a section heading.
    func testCaptureHomeSeeAll() throws {
        let app = sweepLaunch()
        try showHome(in: app)
        hold(2)
        guard let seeAll = hittable("Recently added", in: app, timeout: 8) else {
            throw XCTSkip(
                "Home shows no Recently added heading to open. Buttons: "
                    + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
            )
        }
        seeAll.tap()
        XCTAssertTrue(
            app.navigationBars["Recently added"].waitForExistence(timeout: 5),
            "The heading led to no screen of its own. Navigation bars: "
                + "\(app.navigationBars.allElementsBoundByIndex.map(\.identifier))"
        )
        hold(1.5)
        shutter(app, named: "home-see-all")
    }

    /// The shelves screen: collections and reading lists, both empty on a clean device, each
    /// with a sentence saying what it is for.
    func testCaptureShelves() throws {
        let app = sweepLaunch()
        try openShelves(in: app)
        hold(1)
        shutter(app, named: "shelves")
    }

    /// The shelves screen at the largest accessibility text size.
    func testCaptureShelvesAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openShelves(in: app)
        hold(1)
        shutter(app, named: "shelves-ax5")
    }

    /// Making a collection: the sheet, with the promise that it stays on this device.
    func testCaptureNewCollectionSheet() throws {
        let app = sweepLaunch()
        try openShelves(in: app)
        guard let new = hittable("New", in: app, timeout: 5)
            ?? hittable("New collection", in: app, timeout: 3) else {
            throw XCTSkip(
                "The shelves screen offers no way to make one. Buttons: "
                    + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
            )
        }
        new.tap()
        hold(1)
        // A menu may stand between the control and the sheet, so the collection row is taken
        // when it is offered and the sheet asserted either way.
        if let collection = hittable("New collection", in: app, timeout: 2) { collection.tap() }
        XCTAssertTrue(
            app.staticTexts["Stored on this device. Nothing is sent anywhere."]
                .waitForExistence(timeout: 5)
                || app.textFields.firstMatch.waitForExistence(timeout: 3),
            "Nothing offered a name for the new shelf."
        )
        hold(0.75)
        shutter(app, named: "shelves-new-collection")
    }

    // MARK: - The walk

    /// Home, on screen, proved to be Home.
    private func showHome(in app: XCUIApplication) throws {
        try XCTUnwrap(destination("Home", in: app), "The shell offers no Home tab.").tap()
        XCTAssertTrue(
            app.staticTexts["Home"].waitForExistence(timeout: 10),
            "Tapping Home did not open a screen headed Home."
        )
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
    }

    /// Home → Shelves, which is a link at the foot of the screen rather than a destination.
    private func openShelves(in app: XCUIApplication) throws {
        try showHome(in: app)
        hold(2)
        // **Three ways in, tried in turn, because this row is not what it looks like.** It is
        // a `NavigationLink { destination } label: { HStack }` with `.buttonStyle(.plain)`,
        // and what the accessibility tree makes of that is the platform's decision rather
        // than the app's: the walk passed at the largest text size and failed at the default
        // one, on a screen that had the row plainly on it, first through `hittable` and then
        // through `control`. So each candidate is tapped and the arrival checked, and the
        // failure names every button it could see — which is the only thing that will settle
        // what this row actually is.
        _ = scrollTo(app.staticTexts["Shelves"], in: app, swipes: 8)
        let ways = [app.buttons["Shelves"], app.cells["Shelves"], app.staticTexts["Shelves"]]
        for way in ways where way.exists && way.isHittable {
            way.tap()
            if arrivedAtShelves(app) { return }
        }
        // A coordinate on the row, for a link whose label is drawn but whose element is not
        // the thing that takes the tap.
        let row = app.staticTexts["Shelves"]
        if row.exists {
            // Twice the label's own width to the right of it, which for a seven-letter word
            // is still well inside a phone's row and past whatever element owns the text.
            row.coordinate(withNormalizedOffset: CGVector(dx: 2, dy: 0.5)).tap()
            if arrivedAtShelves(app) { return }
        }
        XCTFail(
            "Nothing on Home opened Shelves. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.map(\.label)). Texts: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
    }

    /// Whether the shelves screen is on top.
    private func arrivedAtShelves(_ app: XCUIApplication) -> Bool {
        app.navigationBars["Shelves"].waitForExistence(timeout: 4)
            || app.staticTexts["Collections"].waitForExistence(timeout: 2)
    }
}
