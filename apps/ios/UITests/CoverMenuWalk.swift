import XCTest

// How a UI test drives the cover's menu, shared by the audits and the walks that choose a cover.
//
// The photo picker is the system's own and runs in another process, so the test cannot fill it.
// `scripts/seed-simulator.mjs` puts one picture in the simulator's Photos library with
// `simctl addmedia`, and the picker shows it as an image whose label begins with `Photo`.

@MainActor
extension XCTestCase {

    /// Opens the cover menu from the edit button on the cover, and says what it holds.
    ///
    /// Throws, rather than returning nothing, when there is no edit button: a walk that went on
    /// regardless would audit whatever screen it happened to be on.
    @discardableResult
    func openTheCoverMenu(in app: XCUIApplication) throws -> [String] {
        let edit = app.buttons["Edit cover"]
        XCTAssertTrue(
            edit.waitForExistence(timeout: 10),
            "The page has no edit button on its cover. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(15).map(\.label))"
        )
        edit.tap()
        // The first row of every menu is choosing a picture.
        let choose = app.buttons.matching(
            NSPredicate(format: "label IN {'Change cover', 'Choose a cover'}")
        ).firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5), "The edit button opened no menu.")
        return app.buttons.allElementsBoundByIndex.map(\.label)
    }

    /// Answers a confirmation with Cancel, whichever way this iOS draws one.
    ///
    /// A dialog drawn as a sheet has a Cancel button. One drawn as a popover beside what raised
    /// it has none, and a tap on the page outside it is the reader's way of saying no.
    func cancelTheDialog(in app: XCUIApplication) {
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 1) {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        }
    }

    /// Chooses the picture the seed put in the Photos library, through the real picker.
    ///
    /// Skipped, not failed, when the picker shows none: a simulator that was not seeded is a
    /// state to say so about, not a defect in the app.
    func pickThePhoto(in app: XCUIApplication) throws {
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,'")).firstMatch
        try XCTSkipUnless(
            photo.waitForExistence(timeout: 15),
            "The photo picker shows no picture. Seed one: node scripts/seed-simulator.mjs --device <udid>."
        )
        // By coordinate: the picker is another process's view, and the element can report
        // itself not hittable while it is on screen and answers a tap.
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Opens a reading list of the mock Kavita server from its card on Home.
    ///
    /// Skipped, with the reason, when the server was not added or is not running: the list
    /// belongs to a fixture this test cannot start.
    func openTheKavitaList(_ name: String, in app: XCUIApplication) throws {
        try XCTUnwrap(destination("Home", in: app)).tap()
        let list = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        _ = list.waitForExistence(timeout: 10)
        try XCTSkipUnless(
            scrollTo(list, in: app, swipes: 12),
            "No shelf called \(name) on Home. Run node scripts/kavita-server.mjs <corpus> --port 5001 "
                + "and add it as a library."
        )
        list.tap()
    }

    /// Whether the open menu holds a row of this name.
    func menuHasRow(_ name: String, in app: XCUIApplication, within seconds: TimeInterval = 3) -> Bool {
        app.buttons[name].waitForExistence(timeout: seconds)
    }
}
