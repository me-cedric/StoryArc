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
        let shelves = app.buttons["Shelves"]
        _ = scrollTo(shelves, in: app, swipes: 8)
        try XCTUnwrap(hittable("Shelves", in: app), "Home offers no way into Shelves.").tap()
        XCTAssertTrue(
            app.navigationBars["Shelves"].waitForExistence(timeout: 5)
                || app.staticTexts["Collections"].waitForExistence(timeout: 3),
            "Shelves opened nothing. Texts: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
    }
}
