import XCTest

// Reaching the player, which needs an audiobook on the device and a session running.
//
// Split out of `PlayerScreenshotTests` when `PlayerAuditTests` arrived and wanted the same
// walk. One copy, for the reason `AuditWalk.opensAPublication` is one: the two copies of that
// predicate drifted, and one of them matched nothing.

@MainActor
extension XCTestCase {

    /// Walks to the library and starts the first audiobook it finds, then pauses it.
    ///
    /// Fails rather than returning when there is none: a capture of a shelf with no audiobook
    /// on it, filed as a picture of the player, is worse than no capture — and an accessibility
    /// audit of the same shelf, filed under "Player", is worse still.
    ///
    /// - Returns: the audiobook's cover on the shelf, for a caller that wants to go back to it.
    @discardableResult
    func openAnAudiobook(in app: XCUIApplication) throws -> XCUIElement {
        try XCTUnwrap(destination("Library", in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)

        let audiobook = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Sea Room")
        ).firstMatch
        // The shelf is a grid and the audiobook is not always above the fold — at the largest
        // accessibility text size a cover is much taller, so far fewer fit. Scroll until it is
        // there rather than asserting on the first screenful, which is how this walk failed at
        // that size and passed at the default one.
        var swipes = 0
        while !audiobook.waitForExistence(timeout: 3), swipes < 6 {
            app.scrollViews.firstMatch.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            audiobook.exists,
            "No audiobook on this device's shelf. Copy packages/test-fixtures/audiobooks "
                + "into the simulator's library folder before running this."
        )
        audiobook.tap()

        // The cover opens the publication's detail screen, and its own button is what opens the
        // publication. It says what a *listener* does now — `PrimaryAction` — where it used to
        // say *Read* for an audiobook, which was a promise the button never kept: it reaches
        // `open(_:at:)` and that has always sent an audiobook to the player.
        // `opensAPublication` matches all four wordings, because which one appears depends on
        // whether an earlier run left a recorded position and a walk must not.
        let open = app.buttons.matching(opensAPublication).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "No way in from the detail screen.")
        open.tap()

        // The player starts asynchronously — the container is read for its chapters first — so
        // this waits for the bar rather than for a frame count.
        let wayIn = app.buttons["Open the player"].firstMatch
        XCTAssertTrue(
            wayIn.waitForExistence(timeout: 10),
            "The compact bar never appeared after opening an audiobook."
        )

        // **Paused, and the wait above is why.** The corpus fixtures are seconds long, so a run
        // that let one play would see the bar the first time and an empty shelf the second —
        // the book having ended, correctly, in between. A paused session keeps its bar, which
        // `CompactPlayerTests` pins, so pausing is what makes this repeatable rather than a
        // race against a six-second audiobook.
        app.buttons["Pause"].firstMatch.tap()
        return audiobook
    }
}
