import XCTest

// Reaching the player, which needs an audiobook on the device and a session running.
//
// Split out of `PlayerScreenshotTests` when `PlayerAuditTests` arrived and wanted the same
// walk. One copy, for the reason `AuditWalk.opensAPublication` is one: the two copies of that
// predicate drifted, and one of them matched nothing.

@MainActor
extension XCTestCase {

    /// Walks to the first destination that has an audiobook on it, starts it, then pauses it.
    ///
    /// **The library first, then downloads.** A reader with a source has their books on the
    /// shelf. A seeded simulator has them on downloads and nowhere else: `seed-simulator.mjs`
    /// writes a finished download, and the library adopts a download when the downloads
    /// destination appears rather than at launch — so a walk that asked the library alone was
    /// looking where the seed cannot put anything.
    ///
    /// Fails rather than returning when neither destination has one: a capture of a shelf with
    /// no audiobook on it, filed as a picture of the player, is worse than no capture — and an
    /// accessibility audit of the same shelf, filed under "Player", is worse still.
    ///
    /// - Returns: the audiobook's cover on the shelf, for a caller that wants to go back to it.
    @discardableResult
    func openAnAudiobook(in app: XCUIApplication) throws -> XCUIElement {
        // `matching` asks the cover's own label; `containing` asked its descendants and there
        // are none. A shelf cell is a single accessibility element — `CoverCell` combines its
        // children explicitly and the downloads shelf's link inherits the same behaviour from
        // SwiftUI — so the title is on the cell, and a descendant query matches nothing.
        let audiobook = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Sea Room")
        ).firstMatch

        // **Downloads first, and the order is the whole point.** A seeded download reaches the
        // library only through `LibraryModel.adoptDownloads()`, and that runs from one place:
        // the downloads destination appearing. Visiting the library first therefore finds
        // nothing, and a walk that then settled on downloads would leave every caller's frame
        // and report name false — `PlayerAuditTests` says "Library with the compact bar" and
        // `PlayerScreenshotTests` files `compact-player` as the same shelf as
        // `library-nothing-playing`. Downloads first makes the adoption happen; the library
        // then holds the book, and the walk ends where its callers say it ends.
        var found = false
        for shelf in ["Downloads", "Library"] where !found {
            try XCTUnwrap(destination(shelf, in: app), "The shell offers no \(shelf) tab.").tap()
            _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
            // The shelf is a grid and the audiobook is not always above the fold — at the largest
            // accessibility text size a cover is much taller, so far fewer fit. Scroll until it is
            // there rather than asserting on the first screenful, which is how this walk failed at
            // that size and passed at the default one.
            var swipes = 0
            while !audiobook.waitForExistence(timeout: 3), swipes < 6 {
                app.scrollViews.firstMatch.swipeUp()
                swipes += 1
            }
            found = audiobook.exists
        }
        XCTAssertTrue(
            found,
            "No audiobook on this device's library or downloads. Put one there: boot the "
                + "simulator, install the app, then run `node scripts/seed-simulator.mjs`. A "
                + "sweep launch clears the download record, so a sweep needs the corpus in the "
                + "device's own library folder instead."
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
