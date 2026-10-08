import XCTest

/// A truncated audiobook, played to its end in the full player.
///
/// Task 2.5, owner answer O12. `truncated.m4b` reports a whole `moov`, three chapters and
/// `isPlayable`, so nothing before playback says the media is short. The engine finds out as
/// it plays: `AVPlayerItemFailedToPlayToEndTime` arrives early, from its read-ahead, with
/// "Invalid sample cursor", and the item then plays on to the nominal end. The player used to
/// end the session on that first report. It now counts the part, carries on, and the finished
/// surface states how much could not be played.
///
/// **It needs `Cut Short` on the device**, which `scripts/seed-simulator.mjs` puts on the
/// Downloads shelf beside `Sea Room`. It fails by name when the shelf has no such book rather
/// than passing on an empty one.
///
/// The photograph is the frame `docs/openspec` task 2.5 is owed:
/// `node scripts/capture-ios.mjs --out <dir> --only PlayerDamageTests --appearance light`,
/// then `dark`.
@MainActor
final class PlayerDamageTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testACutShortBookStatesTheLossWhereItEnds() throws {
        let app = launch()
        try startTheCutShortBook(in: app)

        // The player has to be open before the fixture's six seconds run out, because a book
        // that ends with no player open has no surface left to state anything on.
        let wayIn = app.buttons["Open the player"].firstMatch
        XCTAssertTrue(wayIn.waitForExistence(timeout: 10), "The compact bar never appeared.")
        wayIn.tap()

        let finished = app.staticTexts["Playback stopped"]
        XCTAssertTrue(
            finished.waitForExistence(timeout: 25),
            "The book never reached its end in the open player. Texts on screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))"
        )
        XCTAssertTrue(
            app.staticTexts["1 part could not be played"].waitForExistence(timeout: 3),
            "The finished player says nothing of the part that could not be played. Texts on screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.map(\.label))"
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "player-finished-damaged"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Task 23.6: the damaged ending, photographed as the app draws it.
    ///
    /// The product is expected to say *Playback stopped* and offer *Mark as finished* when the
    /// last part failed. This walk records what the surface shows and, when the button is
    /// there, taps it and photographs the result. It does not assert the button, so a build
    /// that draws *Finished* with no button is photographed rather than hidden.
    func testCaptureDamagedEndingBeforeAndAfterMarking() throws {
        let app = launch()
        try startTheBook("Cut Short", in: app)
        let wayIn = app.buttons["Open the player"].firstMatch
        XCTAssertTrue(wayIn.waitForExistence(timeout: 10), "The compact bar never appeared.")
        wayIn.tap()
        let ended = NSPredicate(format: "label == %@ OR label == %@", "Playback stopped", "Finished")
        XCTAssertTrue(
            app.staticTexts.matching(ended).firstMatch.waitForExistence(timeout: 25),
            "The book never reached its end. Texts: \(app.staticTexts.allElementsBoundByIndex.map(\.label))"
        )
        let heading = app.staticTexts["Playback stopped"].exists ? "Playback stopped" : "Finished"
        XCTAssertTrue(
            app.staticTexts["1 part could not be played"].waitForExistence(timeout: 25),
            "The damage line never appeared. Texts: \(app.staticTexts.allElementsBoundByIndex.map(\.label))"
        )
        let mark = app.buttons["Mark as finished"]
        shutter(app, named: "player-damaged-before")
        XCTContext.runActivity(named: "heading \(heading), button \(mark.exists)") { _ in }
        guard mark.exists else { return }
        mark.tap()
        XCTAssertTrue(app.staticTexts["Finished"].waitForExistence(timeout: 5), "The heading did not change.")
        shutter(app, named: "player-damaged-after")
    }

    /// Task 7.3: a six-second audiobook played to its end, in the open player.
    func testCaptureFinishedAudiobook() throws {
        let app = launch()
        try startTheBook("Sea Room", in: app)
        let wayIn = app.buttons["Open the player"].firstMatch
        XCTAssertTrue(wayIn.waitForExistence(timeout: 10), "The compact bar never appeared.")
        wayIn.tap()
        XCTAssertTrue(app.staticTexts["Finished"].waitForExistence(timeout: 25), "The book never finished.")
        shutter(app, named: "player-finished-audiobook")
    }

    /// Downloads, then the library, the book, and the button that plays it. Left playing: the
    /// walk that follows has seconds, not minutes.
    ///
    /// **Downloads first, because the library adopts a seeded download only when that
    /// destination appears**; `AudiobookWalk` says so at length. And the cover is asked for by
    /// its start, since a Downloads row also carries "Remove the download of Cut Short".
    private func startTheCutShortBook(in app: XCUIApplication) throws {
        try startTheBook("Cut Short", in: app)
    }

    private func startTheBook(_ title: String, in app: XCUIApplication) throws {
        for shelf in ["Downloads", "Library"] {
            try XCTUnwrap(destination(shelf, in: app), "The shell offers no \(shelf) tab.").tap()
            _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        }
        let book = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        var swipes = 0
        while !book.waitForExistence(timeout: 3), swipes < 6 {
            app.scrollViews.firstMatch.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            book.exists,
            "No `\(title)` on this device's library. Install the app, then run "
                + "`node scripts/seed-simulator.mjs --device <udid>`."
        )
        book.tap()
        // A book held in two places opens a list of its copies first. Take the downloaded one.
        let copy = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "On this device")).firstMatch
        if copy.waitForExistence(timeout: 3) { copy.tap() }
        let open = app.buttons.matching(opensAPublication).firstMatch
        XCTAssertTrue(
            open.waitForExistence(timeout: 10),
            "No way in from the detail screen. Buttons: \(app.buttons.allElementsBoundByIndex.map(\.label))"
        )
        open.tap()
    }
}
