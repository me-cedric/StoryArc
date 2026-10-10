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
    /// - Parameter title: how the cover's label begins. `Sea Room` unless a walk needs another
    ///   book, such as the one with a title long enough to be cut in the compact bar. It is the
    ///   start of the label and not any part of it, because a Downloads row also carries a
    ///   *Remove the download of …* button naming the same book.
    /// - Returns: the audiobook's cover on the shelf, for a caller that wants to go back to it.
    @discardableResult
    func openAnAudiobook(in app: XCUIApplication, titled title: String = "Sea Room") throws -> XCUIElement {
        // `matching` asks the cover's own label; `containing` asked its descendants and there
        // are none. A shelf cell is a single accessibility element — `CoverCell` combines its
        // children explicitly and the downloads shelf's link inherits the same behaviour from
        // SwiftUI — so the title is on the cell, and a descendant query matches nothing.
        let audiobook = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", title)
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
        XCTAssertTrue(
            open.waitForExistence(timeout: 10),
            "No way in from the detail screen. Buttons: \(app.buttons.allElementsBoundByIndex.map(\.label))"
        )
        open.tap()

        // The player starts asynchronously — the container is read for its chapters first — so
        // this waits for the bar rather than for a frame count.
        let wayIn = app.buttons["Open the player"].firstMatch
        // **Paused, and the wait is why.** The corpus fixtures are seconds long, so a run that
        // let one play would see the bar the first time and an empty shelf the second — the
        // book having ended, correctly, in between. A paused session keeps its bar, which
        // `CompactPlayerTests` pins, so pausing is what makes this repeatable rather than a
        // race against a six-second audiobook.
        //
        // **Up to three times, when a sibling test left the book near its end.** The fixture's
        // position is kept in the progress store, which no launch argument resets. A test
        // earlier in the same run can leave it a moment from the end, so "Continue listening"
        // plays out before the bar is looked for (2026-09-29), or after the bar appeared and
        // before the pause (2026-10-10), and the session ends with it. A finished book starts
        // over on the next tap.
        for attempt in 0..<3 {
            if attempt > 0 {
                let again = app.buttons.matching(opensAPublication).firstMatch
                if again.waitForExistence(timeout: 3) { again.tap() }
            }
            guard wayIn.waitForExistence(timeout: 6) else { continue }
            pauseWhatPlays(in: app)
            if wayIn.waitForExistence(timeout: 1) { break }
        }
        XCTAssertTrue(
            wayIn.exists,
            "The compact bar never appeared after opening an audiobook. In the bottom strip: "
                + app.buttons.allElementsBoundByIndex
                    .filter { $0.frame.midY > app.frame.height - 220 }
                    .map(\.label)
                    .joined(separator: " | ")
        )
        return audiobook
    }

    /// Opens the full player from the compact bar, then its chapter list.
    func openTheChapterList(in app: XCUIApplication) throws {
        let wayIn = app.buttons["Open the player"].firstMatch
        if wayIn.exists, wayIn.isHittable { wayIn.tap() }
        let chapters = app.buttons["Chapters"].firstMatch
        XCTAssertTrue(chapters.waitForExistence(timeout: 10), "The player offers no chapter list.")
        chapters.tap()
        XCTAssertTrue(app.navigationBars["Chapters"].waitForExistence(timeout: 5), "The chapter list did not open.")
        hold(1)
    }

    /// Picks a playback speed in the player, so a two-second chapter lasts long enough to pause in.
    /// The speed is kept by the app, so a walk that slows the book puts it back to `1`.
    /// `rate` is a regex, because the decimal mark follows the device locale.
    func setSpeed(_ rate: String, in app: XCUIApplication) throws {
        let wayIn = app.buttons["Open the player"].firstMatch
        if wayIn.exists, wayIn.isHittable { wayIn.tap() }
        let speed = app.buttons["Speed"].firstMatch
        XCTAssertTrue(speed.waitForExistence(timeout: 10), "The player offers no speed control.")
        speed.tap()
        let row = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^\(rate).*")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No speed row starts with \(rate).")
        row.tap()
        hold(1)
    }

    /// Puts the book back at its first chapter, paused, so the next run does not start near the end.
    /// A walk that ends in chapter two leaves a six-second book where one more run finishes it, and a
    /// finished book loses its bar before the next walk can look for it.
    func rewindTheBook(in app: XCUIApplication) throws {
        try openTheChapterList(in: app)
        let first = try XCTUnwrap(chapterRows(in: app).first, "The chapter list has no row.")
        first.tap()
        pauseWhatPlays(in: app)
    }

    /// Taps the Pause that can be reached. The bar behind the player sheet has one too, and a tap on it
    /// lands on the sheet.
    func pauseWhatPlays(in app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let pauses = app.buttons.matching(identifier: "Pause").allElementsBoundByIndex
            if let pause = pauses.first(where: \.isHittable) {
                pause.tap()
                return
            }
            hold(0.1)
        }
    }

    /// The chapter rows, top to bottom, each as the label a screen reader is handed.
    func chapterRows(in app: XCUIApplication) -> [XCUIElement] {
        let top = app.navigationBars["Chapters"].frame.maxY
        return app.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && $0.frame.minY >= top && $0.label != "Close" }
            .sorted { $0.frame.minY < $1.frame.minY }
    }
}
