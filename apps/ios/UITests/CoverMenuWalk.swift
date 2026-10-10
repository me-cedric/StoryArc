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

    /// The frame a finger has to hit to open the cover menu.
    ///
    /// A menu on a cover answers `Edit cover` with an outer element as large as the cover and
    /// holds the real button inside it, so the outer frame passes whatever the button measures
    /// (30 pt, measured on 2026-10-09). The button inside is the one a finger lands on. In a
    /// list row the outer element was the whole row until task 27.5 gave the row a second
    /// element, so it is now 44 pt there as well.
    func coverButtonRegion(_ edit: XCUIElement) -> CGRect {
        let inner = edit.buttons.firstMatch
        return inner.exists ? inner.frame : edit.frame
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

    /// Opens a reading list of the mock Kavita server the way a reader does: Home, the Shelves
    /// heading, then the list's card on the Shelves screen.
    ///
    /// Home draws no card for a server's list that is not pinned, so a button for it is not
    /// there to find. The heading is tapped at its words: a tap in the middle of its row
    /// opens nothing.
    ///
    /// Skipped, with the reason, when the server was not added or is not running: the list
    /// belongs to a fixture this test cannot start.
    func openTheKavitaList(_ name: String, in app: XCUIApplication) throws {
        try XCTUnwrap(destination("Home", in: app)).tap()
        // The card's label goes on with its source ("Start here, ada · 127.0.0.1"). A Home row
        // heading of the same name opens the list's titles and not the list (task 26.6).
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(name),")).firstMatch
        _ = card.waitForExistence(timeout: 5)
        // Once the Shelves screen has heard from the server, Home remembers its lists and draws
        // them as cards, and the way in is the card.
        if !scrollTo(card, in: app, swipes: 12) {
            let heading = app.staticTexts["Shelves"]
            try XCTSkipUnless(
                scrollTo(heading, in: app, swipes: 12),
                "Home shows no list called \(name) and no Shelves heading. Run node scripts/kavita-server.mjs "
                    + "<corpus> --port 5001 and run AddMockKavitaTests once."
            )
            heading.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
            try XCTSkipUnless(
                card.waitForExistence(timeout: 10), "The Shelves screen shows no list called \(name)."
            )
        }
        card.tap()
    }

    /// Whether the open menu holds a row of this name.
    func menuHasRow(_ name: String, in app: XCUIApplication, within seconds: TimeInterval = 3) -> Bool {
        app.buttons[name].waitForExistence(timeout: seconds)
    }
}
