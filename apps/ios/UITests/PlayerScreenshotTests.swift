import XCTest

/// Photographs the player, so that `AGENTS.md` section 6's visual proof is repeatable.
///
/// Its own file rather than more of `ScreenshotTests`: that one crossed the 400-line cap
/// the moment these four arrived, and the cut is a real seam — every capture here needs an
/// audiobook on the device's shelf and a session running, which none of the others do.
///
/// The walk they share is ``openAnAudiobook(in:)``. It fails by name when the shelf has no
/// audiobook rather than photographing an empty one, which is the failure `AuditWalk` warns
/// about at length: a check that can silently measure the wrong screen is worse than no
/// check. `docs/designs/screenshots/after-2026-09-01-ios-player/README.md` says how to put
/// one there.
@MainActor
final class PlayerScreenshotTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The library with nothing playing: the control for every capture below it.
    ///
    /// `AGENTS.md` §6: "a screenshot that could look the same for a boring reason needs a
    /// control". The claim the next two captures make is that a compact bar *appears* above
    /// the navigation control and does not displace it — which a picture of the bar cannot
    /// prove on its own, because a tab bar that had always been that high would look
    /// identical. This is the same device, the same shelf, the same moment, with no session
    /// running.
    func testCaptureLibraryWithNothingPlaying() throws {
        let app = launch()
        try XCTUnwrap(destination("Library", in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        settle(1)
        attach(app.screenshot(), named: "library-nothing-playing")
    }

    /// The compact bar, above the navigation control, while an audiobook plays.
    ///
    /// `audio-playback`: the bar "rests above the navigation control, naming the publication
    /// and the chapter being spoken … and it does not displace, cover or resize the
    /// navigation control". Compare against `library-nothing-playing` for the second half:
    /// the four destinations sit where they sat, at the height they were.
    ///
    /// **It needs an audiobook in the library**, which the shared corpus has and this device
    /// only has if somebody put one there. The test states that rather than passing on an
    /// empty shelf, because a capture that silently photographs the wrong thing is the
    /// failure `AuditWalk` warns about at length.
    func testCaptureCompactPlayer() throws {
        let app = launch()
        let book = try openAnAudiobook(in: app)
        _ = book
        attach(app.screenshot(), named: "compact-player")
    }

    /// The full player, opened from the compact bar.
    ///
    /// `audio-playback`: it shows "the cover, the publication, the chapter, the position and
    /// duration, and offers play, pause, skip back, skip forward, a scrub control, the
    /// chapter list, playback speed and a sleep timer".
    func testCaptureFullPlayer() throws {
        let app = launch()
        _ = try openAnAudiobook(in: app)
        try XCTUnwrap(app.buttons["Open the player"].firstMatch).tap()
        settle(2)
        attach(app.screenshot(), named: "full-player")
    }

    /// The full player at the largest accessibility text size.
    ///
    /// `audio-playback` requires that nothing is "truncated to one word and no transport
    /// control is pushed off the screen" there, and a claim that a surface scrolls is worth
    /// exactly as much as the largest text size somebody actually pointed at it.
    func testCaptureFullPlayerAtLargestText() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        _ = try openAnAudiobook(in: app)
        try XCTUnwrap(app.buttons["Open the player"].firstMatch).tap()
        settle(2)
        attach(app.screenshot(), named: "full-player-largest-text")
    }

    /// Walks to the library and starts the first audiobook it finds.
    ///
    /// Fails rather than returning when there is none: a capture of a shelf with no
    /// audiobook on it, filed as a picture of the player, is worse than no capture.
    @discardableResult
    private func openAnAudiobook(in app: XCUIApplication) throws -> XCUIElement {
        try XCTUnwrap(destination("Library", in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)

        let audiobook = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Sea Room")
        ).firstMatch
        // The shelf is a grid and the audiobook is not always above the fold — at the
        // largest accessibility text size a cover is much taller, so far fewer fit. Scroll
        // until it is there rather than asserting on the first screenful, which is how this
        // walk failed at that size and passed at the default one.
        var swipes = 0
        while !audiobook.waitForExistence(timeout: 3), swipes < 6 {
            app.scrollViews.firstMatch.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            audiobook.exists,
            "No audiobook on this device's shelf. Copy packages/test-fixtures/audiobooks "
                + "into the simulator's library folder before capturing."
        )
        audiobook.tap()
        // The cover opens the publication's detail screen, and its own button is what opens
        // the publication. It says what a *listener* does now — `PrimaryAction` — where it used
        // to say *Read* for an audiobook, which was a promise the button never kept: it
        // reaches `open(_:at:)` and that has always sent an audiobook to the player.
        // `opensAPublication` matches all four wordings, because which one appears depends on
        // whether an earlier run left a recorded position and a capture walk must not.
        let open = app.buttons.matching(opensAPublication).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "No way in from the detail screen.")
        open.tap()

        // The player starts asynchronously — the container is read for its chapters first —
        // so this waits for the bar rather than for a frame count.
        let wayIn = app.buttons["Open the player"].firstMatch
        XCTAssertTrue(
            wayIn.waitForExistence(timeout: 10),
            "The compact bar never appeared after opening an audiobook."
        )

        // **Paused, and the wait above is why.** The corpus fixtures are seconds long, so a
        // capture that let one play would photograph the bar the first time and an empty
        // shelf the second — the book having ended, correctly, between the two. A paused
        // session keeps its bar, which `CompactPlayerTests` pins, so pausing is what makes
        // these captures repeatable rather than a race against a six-second audiobook.
        app.buttons["Pause"].firstMatch.tap()
        settle(1)
        return audiobook
    }

    /// Waits, then photographs.
    ///
    /// Chrome animates in and out, and a screenshot taken during either is a picture of a
    /// half-faded bar. `Thread.sleep` blocks the main actor and starves the run loop the
    /// animation needs, so this parks on an expectation instead.
    private func settle(_ seconds: TimeInterval) {
        let settled = XCTestExpectation(description: "waited \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { settled.fulfill() }
        wait(for: [settled], timeout: seconds + 3)
    }

    private func attach(_ shot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
