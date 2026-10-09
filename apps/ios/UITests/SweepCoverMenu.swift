import XCTest

/// The cover's edit button and the menu behind it, photographed.
///
/// Tasks 24.1 and 24.2 of `close-the-audited-gaps`. These replace the stacked text buttons the
/// wave 3 frames showed. The appearance is the simulator's; `capture-ios.mjs --appearance`
/// sets it. The picture is chosen through the real photo picker, which the seed fills.
@MainActor
final class SweepCoverMenuTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A comic has artwork: the edit button on the cover, the menu closed and then open.
    func testCaptureEditButtonAndMenuOnAnArtworkCover() throws {
        let app = sweepLaunch()
        try openFirstPublication(in: app, ofFormat: "CBZ")
        hold(1)
        shutter(app, named: "cover-edit-closed")
        try openTheCoverMenu(in: app)
        hold(0.75)
        shutter(app, named: "cover-menu-open")
    }

    /// A chosen cover: the menu with Remove cover last, then the question before removal.
    func testCaptureChosenCoverMenuAndRemoveDialog() throws {
        let app = sweepLaunch()
        try openFirstPublication(in: app, ofFormat: "CBZ")
        try openTheCoverMenu(in: app)
        app.buttons["Change cover"].tap()
        try pickThePhoto(in: app)
        hold(1)
        shutter(app, named: "cover-chosen")

        try openTheCoverMenu(in: app)
        hold(0.75)
        shutter(app, named: "cover-chosen-menu-open")

        let remove = app.buttons["Remove cover"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "A chosen cover offers no removal.")
        remove.tap()
        XCTAssertTrue(app.staticTexts["Remove this cover?"].waitForExistence(timeout: 5))
        hold(0.75)
        shutter(app, named: "cover-remove-dialog")

        // Leave the simulator as found.
        app.buttons["Remove cover"].tap()
    }

    /// A page with no artwork keeps a visible Add a cover, and it opens the same menu.
    func testCaptureCoverlessAddACoverAndMenu() throws {
        let app = launch()
        try openSeaRoom(in: app)
        let add = app.buttons["Add a cover"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "No Add a cover on a coverless page.")
        hold(1)
        shutter(app, named: "cover-add")
        add.tap()
        XCTAssertTrue(app.buttons["Choose a cover"].waitForExistence(timeout: 5))
        hold(0.75)
        shutter(app, named: "cover-add-menu-open")
    }

    /// The Kavita reading-list cover: before a choice, then chosen with its menu open.
    ///
    /// Needs the mock: `node scripts/kavita-server.mjs <corpus> --port 5001`, added by
    /// `AddMockKavitaTests`. Skipped, with the reason, where it is missing.
    func testCaptureKavitaListCover() throws {
        let app = sweepLaunch()
        try openStartHere(in: app)
        let add = app.buttons["Add a cover"].firstMatch
        let edit = app.buttons["Edit cover"]
        XCTAssertTrue(add.waitForExistence(timeout: 10) || edit.exists, "The list's cover offers nothing.")
        hold(1)
        if add.exists {
            shutter(app, named: "kavita-cover-add")
            add.tap()
            app.buttons["Choose a cover"].tap()
            try pickThePhoto(in: app)
        }
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        hold(1)
        shutter(app, named: "kavita-cover-chosen")
        edit.tap()
        XCTAssertTrue(app.buttons["Send this cover to the server"].waitForExistence(timeout: 5))
        hold(0.75)
        shutter(app, named: "kavita-cover-menu-open")
        app.buttons["Send this cover to the server"].tap()
        XCTAssertTrue(
            app.staticTexts["This changes the cover for everyone who can see that list."]
                .waitForExistence(timeout: 5)
        )
        hold(0.75)
        shutter(app, named: "kavita-cover-send-dialog")
        cancelTheDialog(in: app)

        // Leave the simulator as found.
        try openTheCoverMenu(in: app)
        app.buttons["Remove cover"].tap()
        XCTAssertTrue(app.staticTexts["Remove this cover?"].waitForExistence(timeout: 5))
        app.buttons["Remove cover"].tap()
    }

    /// Sea Room carries no artwork. The shelf groups the title, so this taps on until a page
    /// with a way in arrives, as `SweepCoverChoiceTests` does.
    private func openSeaRoom(in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        XCTAssertTrue(tapSeaRoom(prefix: "Sea Room", in: app), "The shelf never showed Sea Room.")
        for _ in 0..<3 {
            if app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 5) { break }
            if !tapSeaRoom(prefix: "Sea Room, M4B", in: app) { _ = tapSeaRoom(prefix: "Sea Room", in: app) }
            hold(0.5)
        }
        XCTAssertTrue(app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 10))
        hold(1.5)
    }

    private func tapSeaRoom(prefix: String, in app: XCUIApplication) -> Bool {
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
        for _ in 0..<25 {
            if let hit = wanted.allElementsBoundByIndex.first(where: \.isHittable) {
                hit.tap()
                return true
            }
            app.swipeUp(velocity: .fast)
        }
        return false
    }

    /// Home draws the server's reading lists as cards once the mock is added. The list is
    /// `Start here`, and its card is found by its title.
    private func openStartHere(in app: XCUIApplication) throws {
        try XCTUnwrap(destination("Home", in: app)).tap()
        let title = app.staticTexts["Start here"]
        _ = title.waitForExistence(timeout: 10)
        try XCTSkipUnless(
            scrollTo(title, in: app, swipes: 12),
            "Home shows no list called Start here. Run node scripts/kavita-server.mjs on port 5001 and add it."
        )
        title.tap()
    }

    /// The downloads queue with a failed transfer's actions menu open, then the menu for every
    /// transfer. Task 24.3. The queue is injected, so no server is needed.
    func testCaptureQueueMenus() throws {
        let app = sweepLaunch(downloads: SweepDownloadsTests.queue)
        try XCTUnwrap(destination("Downloads", in: app)).tap()
        XCTAssertTrue(app.staticTexts["Coming down now"].waitForExistence(timeout: 10))
        hold(1)
        let failed = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Actions for' AND label CONTAINS 'The Peregrine'")
        ).firstMatch
        XCTAssertTrue(failed.waitForExistence(timeout: 5))
        failed.tap()
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 5))
        hold(0.75)
        shutter(app, named: "downloads-row-menu-open")
        cancelTheDialog(in: app)
        hold(0.5)
        let all = app.buttons["All downloads"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        hold(0.75)
        shutter(app, named: "downloads-all-menu-open")
    }

    /// The publication page in French, for a title on this device: the provenance sentence.
    ///
    /// Task 4.6 of `one-vocabulary-in-four-languages`. French needs the other four states
    /// (a server title, an unreachable server, a removed library, a second place); those need
    /// fixtures this walk does not start.
    func testCaptureFrenchPublicationPage() throws {
        let app = sweepLaunch(language: "fr")
        let tab = app.tabBars.buttons["Bibliothèque"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "No French Library tab.")
        tab.tap()
        waitForTheShelfToSettle(in: app)
        let cover = try XCTUnwrap(coversOnScreen(in: app, ofFormat: "CBZ").first, "No comic on the shelf.")
        cover.tap()
        hold(3)
        shutter(app, named: "detail-provenance-device-fr")
    }
}
