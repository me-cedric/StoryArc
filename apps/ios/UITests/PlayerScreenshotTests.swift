import XCTest

/// Photographs the player, so that `AGENTS.md` section 6's visual proof is repeatable.
///
/// Its own file rather than more of `ScreenshotTests`: that one crossed the 400-line cap
/// the moment these four arrived, and the cut is a real seam — every capture here needs an
/// audiobook on the device's shelf and a session running, which none of the others do.
///
/// The walk they share is `openAnAudiobook(in:)`, in `AudiobookWalk.swift`. It fails by name
/// when the shelf has no audiobook rather than photographing an empty one, which is the
/// failure `AuditWalk` warns about at length: a check that can silently measure the wrong
/// screen is worse than no check. `docs/designs/screenshots/after-2026-09-01-ios-player/
/// README.md` says how to put one there.
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
        try openAnAudiobook(in: app)
        settle(1)
        attach(app.screenshot(), named: "compact-player")
    }

    /// The full player, opened from the compact bar.
    ///
    /// `audio-playback`: it shows "the cover, the publication, the chapter, the position and
    /// duration, and offers play, pause, skip back, skip forward, a scrub control, the
    /// chapter list, playback speed and a sleep timer".
    func testCaptureFullPlayer() throws {
        let app = launch()
        try openAnAudiobook(in: app)
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
        try openAnAudiobook(in: app)
        try XCTUnwrap(app.buttons["Open the player"].firstMatch).tap()
        settle(2)
        attach(app.screenshot(), named: "full-player-largest-text")
    }

    /// The sleep timer, set, with its remaining time on the face of the control.
    ///
    /// `audio-playback` requires that "the remaining time is shown on the player", and until
    /// `audiobooks-and-playback` §5.3 nothing ticked the countdown: `setSleepTimer` stored one and
    /// the only caller of `sleepTimerElapsed` in the tree was a unit test. So this photographs the
    /// control stating `5:00 left` and announcing *Sleep timer* as its name — it announced only the
    /// number before, which is a value with no name.
    ///
    /// **This is one frame, and the requirement wants two.** A number that is displayed and never
    /// moves is the defect §5.3 fixed, so a single picture of `5:00 left` cannot tell the fix from
    /// the bug. The moving is proven instead by `SleepTimerRunningTests` — the count, the hold
    /// while paused, the ramp, the elapsing and the rewind, with the paused hold and the ramp
    /// mutation-checked — and this picture only shows that the number reaches the surface.
    ///
    /// **Why the second frame cannot be taken here yet, which is a defect and not a limit of the
    /// capture.** The countdown moves only while the book plays, and the walk leaves the session
    /// paused on purpose. Pressing any transport control inside the player **dismisses the player**:
    /// `PlayerDock` hosts the player's `.sheet` on a view inside `if let bar = centre.compact`, so
    /// the moment `CompactPlayer`'s value changes — which pressing play does, and crossing a chapter
    /// does — the sheet's host is rebuilt and the presentation is torn down. Measured, not guessed:
    /// a skip-back tap and a chapter-list tap each left the publication page on screen with the
    /// compact bar still playing, and **the same run against the pre-§3.2 `FullPlayerView` failed
    /// identically**, which is what proves the dismissal predates the Close pill's removal.
    ///
    /// Two frames become possible as soon as that is fixed. Until then this states the gap rather
    /// than claiming an exception.
    func testCaptureSleepTimerSet() throws {
        let app = launch()
        try openAnAudiobook(in: app)
        try XCTUnwrap(app.buttons["Open the player"].firstMatch).tap()

        // The label is the *name*, not the face: `audio-playback` asks a screen reader for "a
        // name and, where it carries one, its value", so the control announces "Sleep timer"
        // and carries the remaining time as its value.
        let sleepControl = try XCTUnwrap(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sleep timer"))
                .allElementsBoundByIndex.first { $0.isHittable },
            "The player offers no sleep timer control."
        )
        sleepControl.tap()

        let fiveMinutes = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "5:00")
        ).firstMatch
        XCTAssertTrue(
            fiveMinutes.waitForExistence(timeout: 5),
            "The sleep timer sheet offered no five-minute row. Rows on screen: "
                + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
        )
        fiveMinutes.tap()
        settle(1)

        // Asserted as well as photographed, and the *value* rather than the label: a control that
        // announced `5:00 left` as its name would be a value with no name, which is what this one
        // did before §5.3.
        XCTAssertEqual(
            sleepControl.value as? String,
            "5:00 left",
            "The sleep control does not state the remaining time as its announced value."
        )
        attach(app.screenshot(), named: "sleep-timer-set")
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
