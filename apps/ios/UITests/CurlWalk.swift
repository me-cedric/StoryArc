import XCTest

/// A screenshot taken off the main thread, which is blocked inside `press(...)` while a
/// finger is down. `XCUIScreen.screenshot()` is a plain request to the test daemon, so it
/// answers from any thread.
final class HeldFrames: @unchecked Sendable {
    private(set) var shots: [XCUIScreenshot] = []
    var shot: XCUIScreenshot? { shots.last }
    func take() { shots.append(XCUIScreen.main.screenshot()) }
}

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

    /// The same turn, asked for by a **tap** instead of by a finger that drags (task 8.3).
    ///
    /// `page-transitions` gives Curl one motion, and the drag above was the only thing that
    /// ran it: an edge tap moved the page index and the next page simply appeared, in the one
    /// mode a reader chooses for its fold. The settled frame this leaves looks like
    /// ``testCaptureCurlSettled``'s on purpose — a curl at rest is a page, as this file's own
    /// note says — so what separates them is the **recording** taken around this case, where
    /// the fold stands in the middle of the screen with no finger anywhere near it. That frame
    /// is what a tap could not produce before, and the command is in this walk's README.
    func testCaptureCurlTurnedByATap() throws {
        let app = sweepLaunch()
        try openCurlingComic(in: app)
        // The trailing third, which `comic-reader` gives to the next page.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        hold(2)
        shutter(app, named: "ios-curl-tapped")
    }

    private func labelsOnScreen(in app: XCUIApplication) -> [String] {
        app.descendants(matching: .any).allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
    }

    /// Drags the menu sheet from its half height to its full height. On the 440-point
    /// iPhone 17 Pro Max the half-height sheet ends above the Page turn row, and the row
    /// reports itself hittable under the home indicator, so a tap on it opens nothing.
    private func raiseTheMenu(in app: XCUIApplication) throws {
        let grabber = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Sheet Grabber")).firstMatch
        guard grabber.waitForExistence(timeout: 3) else { return }
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
        )
        hold(1)
    }

    /// Turns forward until the end screen is up, then comes back to the last page.
    private func goToTheLastPage(in app: XCUIApplication) throws {
        let back = app.buttons["Back to the last page"]
        for _ in 0..<24 where !back.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            hold(1.2)
        }
        XCTAssertTrue(back.waitForExistence(timeout: 5), "No end screen after 24 forward taps.")
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 8), "The end screen did not close.")
        hold(1.5)
    }

    /// Task 8.5: a forward drag held on the last page. Run under `simctl recordVideo`: a
    /// still cannot be taken while a finger is down, and the held part of this drag is what
    /// the recording is for. The frame after release is the control.
    func testCaptureCurlLastPageHeld() throws {
        let app = sweepLaunch()
        try openCurlingComic(in: app)
        try goToTheLastPage(in: app)
        shutter(app, named: "ios-curl-last-page-before-drag")
        try heldDrag(in: app, named: "ios-curl-last-page-held")
        hold(2)
        shutter(app, named: "ios-curl-last-page-released")
    }

    /// Task 8.5: the held drag on the last page, reached by turning forward and never
    /// leaving for the end screen. Photographs the drag from threads that do not wait on the
    /// finger, because `press(...)` returns only when the finger lifts.
    func testCaptureCurlLastPageHeldFromTurns() throws {
        let app = sweepLaunch()
        try openCurlingComic(in: app)
        for _ in 0..<2 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            hold(1.6)
        }
        shutter(app, named: "ios-curl-last-page-turns-before-drag")
        try heldDrag(in: app, named: "ios-curl-last-page-turns-held", to: 0.3)
    }

    /// Task 8.5, the control: the same held drag on the first page, where a sheet lies beneath.
    func testCaptureCurlFirstPageHeld() throws {
        let app = sweepLaunch()
        try openCurlingComic(in: app)
        try heldDrag(in: app, named: "ios-curl-first-page-held")
    }

    /// A slow drag to 66 percent (or to `dx`), held for five seconds, photographed while it is held.
    ///
    /// The press call blocks until the finger lifts, so the frames are asked for from other
    /// threads, at a spread of times. The first may precede the touch; the rest are the drag.
    private func heldDrag(in app: XCUIApplication, named name: String, to dx: CGFloat = 0.66) throws {
        let done = XCTestExpectation(description: "the held frames are taken")
        let frames = HeldFrames()
        for seconds in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0] {
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { frames.take() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4.5) { done.fulfill() }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)),
            withVelocity: .slow,
            thenHoldForDuration: 5
        )
        wait(for: [done], timeout: 10)
        for (n, held) in frames.shots.enumerated() { shutter(shot: held, named: "\(name)-\(n)") }
    }

    /// Task 8.5: a tap past the last page curls onto the end screen, and the last page does
    /// not show again before it. Run under `simctl recordVideo`.
    func testCaptureCurlLastPageTapped() throws {
        let app = sweepLaunch()
        try openCurlingComic(in: app)
        try goToTheLastPage(in: app)
        hold(3)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        hold(3)
        shutter(app, named: "ios-curl-last-page-landed")
    }

    /// Task 8.16: Curl at rest on a page taller than the screen, at Fit to Width.
    func testCaptureCurlAtRestFitWidth() throws {
        let app = sweepLaunch()
        try openCurlingComic(in: app, named: "Tall Pages", fit: "Width")
        hold(1)
        shutter(app, named: "ios-curl-rest-fit-width")
    }

    /// Task 8.16: a PDF page with a saved mark, in Curl at rest. The mark is made with the
    /// selection menu, then the page is photographed with the menu gone.
    func testCaptureCurlRestPdfMarks() throws {
        let app = sweepLaunch()
        try openCurlingComic(in: app, named: "Field Notes")
        for y in [0.27, 0.30, 0.33, 0.36, 0.24] {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: y)).press(forDuration: 1.4)
            hold(1)
            if app.buttons["Yellow"].exists { break }
        }
        let yellow = app.buttons["Yellow"]
        XCTAssertTrue(
            yellow.waitForExistence(timeout: 3),
            "No selection menu. Buttons: \(app.buttons.allElementsBoundByIndex.map(\.label).prefix(40))"
        )
        yellow.tap()
        hold(2)
        shutter(app, named: "ios-curl-rest-pdf-marks")
    }

    /// Task 8.16, the control: the same page at the same fit in Slide, which already honoured it.
    func testCaptureSlideRestFitWidth() throws {
        let app = sweepLaunch()
        try openCurlingComic(in: app, named: "Tall Pages", fit: "Width", mode: "Slide")
        hold(1)
        shutter(app, named: "ios-slide-rest-fit-width")
    }

    /// Task 8.16: the same page zoomed, then panned sideways. The page must pan and not turn.
    func testCaptureCurlAtRestZoomedAndPanned() throws {
        let app = sweepLaunch()
        try openCurlingComic(in: app, named: "Tall Pages", fit: "Width")
        let centre = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        centre.doubleTap()
        hold(1.5)
        shutter(app, named: "ios-curl-rest-zoomed")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)),
            withVelocity: .default,
            thenHoldForDuration: 0.2
        )
        hold(1.5)
        shutter(app, named: "ios-curl-rest-zoomed-panned")
    }

    /// Opens the fixed-layout comic and puts it in Curl, proving the mode took.
    ///
    /// Through the app's own picker rather than an injected preference: the transition lives
    /// inside the `app.storyarc.themes` blob as one field of a per-shelf `ShelfSettings`, so
    /// injecting it would mean hand-writing a `ShelfMemory` encoding in a test bundle that
    /// cannot see `StoryArcCore`. Driving the picker also exercises the path a reader takes.
    func openCurlingComic(
        in app: XCUIApplication,
        named title: String = "Fine Print",
        fit: String? = nil,
        mode: String = "Curl"
    ) throws {
        try openPublication(named: title, in: app)
        try openReaderMenu(in: app)
        try raiseTheMenu(in: app)
        try XCTUnwrap(
            rowInTheMenu("Page turn", in: app),
            "The menu offers no Page turn row. Buttons: \(app.buttons.allElementsBoundByIndex.prefix(30).map(\.label))"
        ).tap()
        // Asked of any descendant rather than of `buttons`, for the reason the sweep's own
        // transition walk gives: what the platform calls a menu row is not this file's
        // business, and it has changed between releases.
        let curl = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", mode)).firstMatch
        guard curl.waitForExistence(timeout: 8) else {
            // Not a silent skip: if Curl is missing from a *comic*'s picker then either the
            // device reported it cannot curl or the row has been renamed, and both are
            // findings rather than reasons to photograph nothing.
            XCTFail(
                "The Transition picker offers no Curl on a fixed-layout publication, where "
                    + "`needsTwoRasters` does not apply. On screen: "
                    + "\(Array(labelsOnScreen(in: app).suffix(25)))"
            )
            return
        }
        curl.tap()
        hold(1)
        if let fit {
            try XCTUnwrap(rowInTheMenu("Fit", in: app), "The menu offers no Fit row.").tap()
            let wanted = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", fit)).firstMatch
            XCTAssertTrue(wanted.waitForExistence(timeout: 8), "The Fit row offers no \(fit).")
            wanted.tap()
            hold(1)
        }
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
        // A cover can settle half past the bottom edge, never hittable, and the next swipe
        // carries it past the top. The shelf's alphabetical index puts the letter's first row
        // at the top instead. `SweepComicReaderTests.openPublication` measured this first.
        if found == nil, let initial = title.first.map({ String($0).uppercased() }) {
            let jump = app.buttons.matching(NSPredicate(format: "label == %@", "Jump to \(initial)")).firstMatch
            if jump.isHittable {
                jump.tap()
                for _ in 0..<4 where found == nil {
                    found = wanted.allElementsBoundByIndex.first(where: \.isHittable)
                    if found == nil { app.swipeUp() }
                }
            }
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
