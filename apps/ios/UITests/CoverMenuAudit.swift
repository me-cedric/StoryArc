import XCTest

/// The cover's actions, audited: one edit button on the cover, one menu behind it, and a
/// hit region a finger can find.
///
/// Tasks 24.1, 24.2 and 24.5 of `close-the-audited-gaps`. The owner found "Change cover",
/// "Remove cover" and "Send this cover to the server" stacked as text, each as tall as its
/// words. Apple's hit-region audit measured the stacked buttons at 18 pt on 2026-10-08, so
/// these fail on the stack and pass on the menu.
///
/// **The audit's own threshold is lower than the guideline's.** It let a 30 pt button
/// through, so each test also reads the frame of the control it changed and asks for 44 × 44
/// pt, which is what the Human Interface Guidelines ask.
///
/// These are `AccessibilityAuditTests`' own tests, in a file of their own because that class
/// sits at the 400-line cap.
extension AccessibilityAuditTests {

    /// A comic has artwork, so its page carries the edit button on the cover.
    func testPublicationPageCoverActionsPassTheHitRegionAudit() throws {
        let app = launch()
        try openFirstPublication(in: app, ofFormat: "CBZ")
        try audit(app, named: "Publication page with a cover", types: .hitRegion)

        let edit = app.buttons["Edit cover"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "The cover has no edit button.")
        let region = coverButtonRegion(edit)
        XCTAssertGreaterThanOrEqual(region.width, 44, "The edit button is narrower than 44 pt: \(region).")
        XCTAssertGreaterThanOrEqual(region.height, 44, "The edit button is shorter than 44 pt: \(region).")
    }

    /// A page with no artwork keeps a visible "Add a cover", and it opens the same menu.
    ///
    /// `Sea Room` is the corpus's chaptered audiobook and carries no artwork of any kind, so
    /// its page draws the coverless well. There is no edit button on a glyph, and nothing to
    /// remove or send, so the menu is the two ways of finding a picture.
    func testACoverlessPageOffersAddACoverAsOneMenu() throws {
        let app = launch()
        let covers = try coversOnTheShelf(in: app)
        let sea = try XCTUnwrap(
            covers.map(\.label).first { $0.hasPrefix("Sea Room") },
            "This device's shelf shows no cover for Sea Room. Seed it: node scripts/seed-simulator.mjs"
        )
        try openFirstPublication(in: app, named: sea)
        try audit(app, named: "Publication page with no cover", types: .hitRegion)

        let add = app.buttons["Add a cover"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "A page with no cover offers no Add a cover.")
        XCTAssertGreaterThanOrEqual(add.frame.height, 44, "Add a cover is shorter than 44 pt.")
        XCTAssertFalse(app.buttons["Edit cover"].exists, "A glyph has an edit button.")

        add.tap()
        XCTAssertTrue(app.buttons["Choose a cover"].waitForExistence(timeout: 5), "The menu offers no picture.")
        XCTAssertTrue(app.buttons["Find a cover on the web"].exists, "The menu offers no web search.")
        XCTAssertFalse(app.buttons["Remove cover"].exists, "A page with no chosen cover offers its removal.")
        XCTAssertFalse(
            app.buttons["Send this cover to the server"].exists,
            "A publication on this device offers to send its cover to a server."
        )
    }

    /// A chosen cover, through the real picker: the menu, its audit, and the question before
    /// the removal.
    ///
    /// Removal deletes the stored picture, so it asks first, and Cancel keeps the picture: the
    /// menu still offers its removal afterwards. Confirming removes it, which also leaves this
    /// simulator as the test found it.
    func testAChosenCoverIsAuditedAndRemovalAsksFirst() throws {
        let app = launch()
        try openFirstPublication(in: app, ofFormat: "CBZ")

        try openTheCoverMenu(in: app)
        app.buttons["Change cover"].tap()
        try pickThePhoto(in: app)

        try openTheCoverMenu(in: app)
        let remove = app.buttons["Remove cover"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "A chosen cover offers no removal.")
        XCTAssertGreaterThan(
            remove.frame.minY, app.buttons["Change cover"].frame.minY,
            "Removal is not the last row of the menu."
        )
        try audit(app, named: "Cover menu with a chosen cover", types: .hitRegion)

        remove.tap()
        XCTAssertTrue(
            app.staticTexts["Remove this cover?"].waitForExistence(timeout: 5),
            "Removing a chosen cover asked nothing first."
        )
        cancelTheDialog(in: app)

        try openTheCoverMenu(in: app)
        XCTAssertTrue(menuHasRow("Remove cover", in: app), "Cancel removed the chosen picture.")

        app.buttons["Remove cover"].tap()
        XCTAssertTrue(app.staticTexts["Remove this cover?"].waitForExistence(timeout: 5))
        app.buttons["Remove cover"].tap()

        try openTheCoverMenu(in: app)
        XCTAssertFalse(
            app.buttons["Remove cover"].waitForExistence(timeout: 2),
            "Confirming did not remove the chosen picture."
        )
    }

    /// The Kavita reading-list cover, which stacked three buttons beside a 59 pt thumbnail.
    ///
    /// Needs `node scripts/kavita-server.mjs <corpus> --port 5001` and the server added in
    /// Settings > Your libraries, the way `AddMockKavitaTests` describes. Skipped, with the
    /// reason, where either is missing. The send row asks first, and Cancel sends nothing.
    func testKavitaListCoverPassesTheHitRegionAudit() throws {
        let app = launch()
        try openTheKavitaList("Start here", in: app)

        let add = app.buttons["Add a cover"].firstMatch
        let edit = app.buttons["Edit cover"]
        XCTAssertTrue(
            add.waitForExistence(timeout: 10) || edit.exists,
            "The list's cover has neither Add a cover nor an edit button."
        )
        try audit(app, named: "Kavita reading list cover", types: .hitRegion)
        if add.exists {
            XCTAssertGreaterThanOrEqual(add.frame.height, 44, "Add a cover is shorter than 44 pt.")
            add.tap()
            XCTAssertTrue(app.buttons["Choose a cover"].waitForExistence(timeout: 5), "The menu offers no picture.")
            XCTAssertFalse(app.buttons["Remove cover"].exists, "A list with no chosen cover offers its removal.")
            app.buttons["Choose a cover"].tap()
            try pickThePhoto(in: app)
        }

        XCTAssertTrue(edit.waitForExistence(timeout: 10), "A chosen cover left the list with no edit button.")
        // One control, not an element as large as the row around a button (task 27.5).
        XCTAssertLessThanOrEqual(edit.frame.height, 48, "The edit button sits in an outer element: \(edit.frame).")
        let region = coverButtonRegion(edit)
        XCTAssertGreaterThanOrEqual(region.width, 44, "The edit button is narrower than 44 pt: \(region).")
        XCTAssertGreaterThanOrEqual(region.height, 44, "The edit button is shorter than 44 pt: \(region).")
        try audit(app, named: "Kavita reading list, a cover chosen", types: .hitRegion)

        edit.tap()
        let send = app.buttons["Send this cover to the server"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "The menu offers no send row on a list that is the reader's.")
        let remove = app.buttons["Remove cover"]
        XCTAssertTrue(remove.exists, "A chosen cover offers no removal.")
        XCTAssertGreaterThan(remove.frame.minY, send.frame.minY, "Removal is not the last row of the menu.")
        try audit(app, named: "Kavita cover menu", types: .hitRegion)

        send.tap()
        XCTAssertTrue(
            app.staticTexts["This changes the cover for everyone who can see that list."].waitForExistence(timeout: 5),
            "Sending the cover asked nothing first."
        )
        cancelTheDialog(in: app)

        try openTheCoverMenu(in: app)
        app.buttons["Remove cover"].tap()
        XCTAssertTrue(app.staticTexts["Remove this cover?"].waitForExistence(timeout: 5))
        app.buttons["Remove cover"].tap()
        XCTAssertTrue(
            app.buttons["Add a cover"].firstMatch.waitForExistence(timeout: 10),
            "Confirming did not remove the picture."
        )
    }
}
