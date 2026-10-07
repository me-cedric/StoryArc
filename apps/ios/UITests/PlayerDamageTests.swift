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

        let finished = app.staticTexts["Finished"]
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

    /// Downloads, then the library, the book, and the button that plays it. Left playing: the
    /// walk that follows has seconds, not minutes.
    ///
    /// **Downloads first, because the library adopts a seeded download only when that
    /// destination appears**; `AudiobookWalk` says so at length. And the cover is asked for by
    /// its start, since a Downloads row also carries "Remove the download of Cut Short".
    private func startTheCutShortBook(in app: XCUIApplication) throws {
        for shelf in ["Downloads", "Library"] {
            try XCTUnwrap(destination(shelf, in: app), "The shell offers no \(shelf) tab.").tap()
            _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        }
        let book = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Cut Short")).firstMatch
        var swipes = 0
        while !book.waitForExistence(timeout: 3), swipes < 6 {
            app.scrollViews.firstMatch.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            book.exists,
            "No `Cut Short` on this device's library. Install the app, then run "
                + "`node scripts/seed-simulator.mjs --device <udid>`."
        )
        book.tap()
        let open = app.buttons.matching(opensAPublication).firstMatch
        // Two copies of the book are on the device, the seeded download and the one the
        // library scanned, so the cover opens the list of copies first. Choose the first.
        if !open.waitForExistence(timeout: 4) {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Cut Short, ")).firstMatch.tap()
        }
        XCTAssertTrue(
            open.waitForExistence(timeout: 10),
            "No way in from the detail screen. Buttons: \(app.buttons.allElementsBoundByIndex.map(\.label))"
        )
        open.tap()
    }
}
