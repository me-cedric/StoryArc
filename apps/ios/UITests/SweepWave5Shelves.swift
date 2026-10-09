import XCTest

/// Wave 5 frames of pinned shelves (`one-library-three-destinations` 2.1): the shelf menu
/// with Pin to Home and Unpin from Home, Home with a pinned collection and a pinned reading
/// list, and Home after both are unpinned.
///
/// Ordered: `testSetupShelves` makes one collection and one reading list and puts two
/// publications in each. The three capture tests then each start by putting both shelves
/// back to unpinned, so any run order of them gives the same frames.
@MainActor
final class SweepWave5ShelvesTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func openShelves(_ app: XCUIApplication) throws {
        try w5Tab("Home", in: app)
        hold(3)
        for name in ["Collections", "Shelves", "Reading lists"] {
            let ways = [app.buttons[name], app.cells[name], app.staticTexts[name]]
            for way in ways where way.exists && way.isHittable {
                way.tap()
                hold(2)
                if app.staticTexts["Shelves"].exists, app.buttons["BackButton"].exists { return }
            }
        }
        throw Wave5Failure.because("Home offered no way into Shelves.")
    }

    private func make(_ kind: String, named name: String, in app: XCUIApplication) throws {
        try XCTUnwrap(hittable(kind, in: app, timeout: 5), "No \(kind) button").tap()
        hold(1)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        hold(0.5)
        if app.buttons["Continue"].exists { app.buttons["Continue"].tap(); hold(0.5) }
        try XCTUnwrap(hittable("Create", in: app, timeout: 3)).tap()
        hold(1.5)
    }

    private func add(_ title: String, to shelf: String, in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        _ = app.buttons.matching(NSPredicate(format: "label CONTAINS ', '")).firstMatch.waitForExistence(timeout: 20)
        hold(2)
        try coverNamed(title, in: app).press(forDuration: 1.2)
        hold(1.2)
        try XCTUnwrap(app.buttons["Add to…"].firstMatch).tap()
        hold(1.2)
        let target = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", shelf)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 4), "No \(shelf) in the Add to menu.")
        target.tap()
        hold(1.5)
    }

    /// The shelf card whose label starts with a name, on the Shelves screen.
    private func card(_ name: String, in app: XCUIApplication) throws -> XCUIElement {
        let match = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 8), "The Shelves screen shows no \(name).")
        return match
    }

    /// Opens the shelf's menu, and unpins it first when it is pinned. Leaves the menu closed.
    private func normalise(_ name: String, in app: XCUIApplication) throws {
        try card(name, in: app).press(forDuration: 1.2)
        hold(1)
        let unpin = app.buttons["Unpin from Home"]
        if unpin.exists {
            unpin.tap()
            hold(1.2)
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1)).tap()
            hold(0.8)
        }
    }

    func testSetupShelves() throws {
        let app = sweepLaunch(grouping: "issues")
        try openShelves(app)
        try make("New collection", named: "Favourites", in: app)
        try make("New reading list", named: "Start here", in: app)
        app.buttons["BackButton"].tap()
        hold(1)
        try add("Fine Print", to: "Favourites", in: app)
        try add("Paper Lanterns", to: "Favourites", in: app)
        try add("Tidal Reach", to: "Start here", in: app)
        try add("Bright Panels", to: "Start here", in: app)
    }

    /// The shelf's menu offers Pin to Home, and after pinning offers Unpin from Home.
    func testCapturePinMenus() throws {
        let app = sweepLaunch()
        try openShelves(app)
        try normalise("Favourites", in: app)
        try normalise("Start here", in: app)
        try card("Favourites", in: app).press(forDuration: 1.2)
        hold(1)
        XCTAssertTrue(app.buttons["Pin to Home"].exists, "The menu offers no Pin to Home.")
        shutter(app, named: "shelf-menu-pin-to-home")
        app.buttons["Pin to Home"].tap()
        hold(1.5)
        try card("Favourites", in: app).press(forDuration: 1.2)
        hold(1)
        XCTAssertTrue(app.buttons["Unpin from Home"].exists, "The menu offers no Unpin from Home.")
        shutter(app, named: "shelf-menu-unpin-from-home")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1)).tap()
        hold(0.8)
    }

    /// Home with the collection and the reading list both pinned.
    func testCaptureHomePinnedBoth() throws {
        let app = sweepLaunch()
        try openShelves(app)
        for name in ["Favourites", "Start here"] {
            try normalise(name, in: app)
            try card(name, in: app).press(forDuration: 1.2)
            hold(1)
            try XCTUnwrap(app.buttons["Pin to Home"].firstMatch, "No Pin to Home on \(name).").tap()
            hold(1.5)
        }
        app.buttons["BackButton"].tap()
        hold(1)
        try w5Tab("Home", in: app)
        hold(3)
        app.swipeUp()
        hold(1.5)
        shutter(app, named: "home-pinned-collection-and-list")
    }

    /// Home after both are unpinned.
    func testCaptureHomeAfterUnpin() throws {
        let app = sweepLaunch()
        try openShelves(app)
        try normalise("Favourites", in: app)
        try normalise("Start here", in: app)
        app.buttons["BackButton"].tap()
        hold(1)
        try w5Tab("Home", in: app)
        hold(3)
        app.swipeUp()
        hold(1.5)
        shutter(app, named: "home-after-unpin")
    }
}
