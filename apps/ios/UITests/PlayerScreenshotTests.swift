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
