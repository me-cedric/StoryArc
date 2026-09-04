import XCTest

/// The page curl on iOS, photographed **mid-gesture**, which is the only way to see it.
///
/// `reader-theming-and-page-transitions` §4.3 shipped the curl on both platforms and could
/// verify only one: Android was driven frame by frame with held `motionevent` gestures on the
/// emulator, and iOS was recorded as "built and compiles, and is not visually verified". This
/// file is that verification.
///
/// **A curl at rest is a page.** Every existing reader walk photographs a settled page, so a
/// curl that never ran, ran backwards, or drew the wrong page would look identical in all of
/// them. What separates the modes is a frame taken while a finger is down and has not yet
/// lifted — `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` is the one
/// XCUITest primitive that leaves the gesture open long enough to photograph.
///
/// What each frame has to show, taken from the Android verification so the two platforms are
/// judged against one description rather than two:
///
/// - the crease sits where the finger is, and moves when the finger moves;
/// - the turned sheet shows the page's **back** — the same pixels mirrored about the crease and
///   dimmed, because a mirrored image at full brightness reads as a reflection rather than as
///   paper;
/// - the leading edge catches light, and the revealed page is darkest against the crease, which
///   is the only place a lifted page can cast a shadow;
/// - releasing past halfway completes the turn rather than springing back.
///
/// The curl is offered on a **comic** and not on reflowable text: it needs the incoming page as
/// a second texture before it is on screen, which over live web content means a second
/// offscreen navigator or a snapshot round-trip. `PageTransition.needsTwoRasters` is that rule,
/// and §4.3b owns lifting it — so this walk opens *Fine Print*, which is fixed-layout.
@MainActor
final class CurlWalkTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// **There is no mid-gesture test here, and that is a finding rather than an omission.**
    ///
    /// This file first held two: a drag to 50% of the width and one to 22%, each using
    /// `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` and shooting after
    /// it. Both passed, and both photographed a **settled** page — because that call returns
    /// after the whole gesture, the hold *and the lift* included. The two frames were read as
    /// a curl that did not track the finger (a crease at 95.4% of the width with the finger at
    /// 50%, and at 2% with the finger at 22%) before the arithmetic gave the walk away: 0.42
    /// of a turn springs back and 0.70 completes, which is exactly `CurlTurn.settles`. The
    /// harness was wrong, not the shader.
    ///
    /// XCUITest has no primitive that leaves a touch down across a screenshot, so the curl is
    /// verified from a **screen recording** instead — `xcrun simctl io <udid> recordVideo`
    /// around ``testCaptureCurlSettled``, frames pulled with `ffmpeg -vf fps=20`, and the fold
    /// measured per frame. That also discharges §7.5, which asks for a recording on each
    /// platform because a still cannot show an interruptible gesture. The command and the
    /// measurements are in `docs/designs/screenshots/ios-curl-2026-09-05/README.md`.

    /// The page after the turn completes, which is what proves the gesture did something.
    ///
    /// A curl that renders beautifully and then springs back is the third bug the Android pass
    /// found — the release decision read a progress that had not been written yet — and it is
    /// invisible in any mid-gesture frame.
    func testCaptureCurlSettled() throws {
        let app = sweepLaunch()
        try openCurlingComic(in: app)
        let page = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        page.press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)),
            withVelocity: .default,
            thenHoldForDuration: 0.05
        )
        hold(2)
        shutter(app, named: "ios-curl-settled")
    }

    /// Opens the fixed-layout comic and puts it in Curl, proving the mode took.
    ///
    /// Through the app's own picker rather than an injected preference: the transition lives
    /// inside the `app.storyarc.themes` blob as one field of a per-shelf `ShelfSettings`, so
    /// injecting it would mean hand-writing a `ShelfMemory` encoding in a test bundle that
    /// cannot see `StoryArcCore`. Driving the picker also exercises the path a reader takes.
    private func openCurlingComic(in app: XCUIApplication) throws {
        try openPublication(named: "Fine Print", in: app)
        try openReaderMenu(in: app)
        try XCTUnwrap(hittableRow("Transition", in: app), "The menu offers no Transition row.")
            .tap()
        // Asked of any descendant rather than of `buttons`, for the reason the sweep's own
        // transition walk gives: what the platform calls a menu row is not this file's
        // business, and it has changed between releases.
        let curl = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Curl")).firstMatch
        guard curl.waitForExistence(timeout: 8) else {
            // Not a silent skip: if Curl is missing from a *comic*'s picker then either the
            // device reported it cannot curl or the row has been renamed, and both are
            // findings rather than reasons to photograph nothing.
            XCTFail(
                "The Transition picker offers no Curl on a fixed-layout publication, where "
                    + "`needsTwoRasters` does not apply. On screen: "
                    + "\(app.descendants(matching: .any).allElementsBoundByIndex.prefix(30).map(\.label))"
            )
            return
        }
        curl.tap()
        hold(1)
        // **Dismissed by its own button, not by a tap above it.** A tap at the top of the
        // screen lands on the sheet's own dimmed backdrop in this presentation and leaves the
        // sheet up — the first run of this walk photographed the menu with *Transition: Curl*
        // showing and no page behind it, which proved the picker worked and nothing else.
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The reader menu offers no Done.")
        done.tap()
        // The page must be unobscured and the chrome timed out before a drag means anything.
        XCTAssertTrue(
            done.waitForNonExistence(timeout: 8),
            "The reader menu did not close, so a drag would land on the sheet."
        )
        hold(6)
    }

    /// The shelf → publication → reader path, shared with the sweep's comic walks.
    private func openPublication(named title: String, in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        var found: XCUIElement?
        for _ in 0..<8 where found == nil {
            found = wanted.allElementsBoundByIndex.first(where: \.isHittable)
            if found == nil { app.swipeUp() }
        }
        try XCTSkipUnless(found != nil, "This device's shelf never showed a cover for “\(title)”.")
        found?.tap()

        guard app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 8),
              let action = app.buttons.matching(opensAPublication)
                  .allElementsBoundByIndex.first(where: \.isHittable)
        else { throw XCTSkip("“\(title)”'s page offered no hittable way to open it.") }
        action.tap()

        XCTAssertTrue(
            app.buttons["Close"].waitForExistence(timeout: 15),
            "Opening “\(title)” reached no reader — there is no way out on screen."
        )
        hold(2)
    }

    /// Reveals the chrome and opens the menu.
    private func openReaderMenu(in app: XCUIApplication) throws {
        hold(6)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(
            app.buttons["Menu"].waitForExistence(timeout: 5),
            "A centre tap revealed no chrome."
        )
        try XCTUnwrap(revealed("Menu", in: app), "The reader revealed no menu to open.").tap()
        XCTAssertTrue(
            hittableRow("Contents", in: app) != nil,
            "The menu did not open: it offers no Contents row."
        )
    }
}
