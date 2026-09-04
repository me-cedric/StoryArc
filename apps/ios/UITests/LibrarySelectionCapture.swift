import XCTest

/// Photographs the chrome a selection puts up, in the states the change is about.
///
/// An extension rather than more methods in `ScreenshotTests.swift`, which is one line under
/// the length the linter warns at — `SkippedNoticeCapture.swift` and `AppIconCapture.swift`
/// split off for the same reason, and `capture-ios.mjs` runs the whole class, so these are
/// picked up wherever they are declared. The class-qualified name is what
/// `docs/designs/screenshots/ios-sweep-2026-09-02/README.md` invokes them by, and it is
/// `ScreenshotTests/…` — so they stay here rather than moving to a class of their own.
///
/// **`testCaptureLibrarySelectingAtTheEnd`, in `ScreenshotTests`, is not enough on its own.**
/// It photographs the mode with nothing picked and the shelf scrolled to its end, which is
/// the frame that settles the inset — and the inset was never the defect. What was wrong was
/// the shape: a full-bleed grey slab with a hard top edge, holding a count and a *Done* and
/// three bare glyphs, stacked above the rounded glass tab bar. Two bottom bars at once. So
/// these walks photograph the parts that walk cannot:
///
/// - the capsule **inert**, at the top of the shelf, which is the state §3b.4 chose on
///   purpose — shown rather than hidden at nought picked;
/// - the capsule **live**, with covers picked, where the tab bar's absence is visible and
///   the count is in the navigation bar instead;
/// - both at the **largest accessibility text size**, which is the only thing that can say
///   which branch of the `ViewThatFits` in `BulkActionBar` a real phone takes.
///
/// ## Three things were wrong with the first version of this file, and each could have
/// filed a picture of the wrong screen
///
/// 1. **It launched with `launch()`**, which sets a content-size category and nothing else.
///    Every shelf choice this app has persists in `UserDefaults`, the app's *stored*
///    appearance outranks the simulator's, and this device has carried `oledDark` — so a
///    `--appearance light` run of it could produce a true-black frame under a light
///    filename. `sweepLaunch` pins the appearance to `system` and every shelf key besides;
///    `SweepWalk.swift` records the measurement.
/// 2. **It picked `shelf.buttons` by index.** That query is what
///    ``XCTestCase/realCovers(in:)`` exists to replace: on this device the band where covers
///    are drawn also holds the skipped-publications notice's two controls, so a walk that
///    tapped the first two tapped *What couldn't be opened* and *Dismiss* and photographed a
///    shelf at nought picked under a filename saying two.
/// 3. **Nothing proved the picks landed.** `XCTAssertGreaterThan(picking, 0)` asserted that
///    the *query* had matched something, not that the shelf had changed — and the count is
///    in the navigation bar now, which makes the proof a one-line read of the title.
extension ScreenshotTests {

    /// The shelf in selection mode with nothing picked, which is a deliberate state.
    ///
    /// §3b.4: the actions are **shown rather than hidden** at nought, because chrome that
    /// arrives on the first pick appears under a thumb that is mid-tap and changes the
    /// shelf's bottom inset in the middle of a scroll. So this frame is not the boring half
    /// of the pair — it is the picture of the decision, and the thing to look at in it is
    /// that the capsule is there and dimmed while the way out is not.
    func testCaptureLibrarySelectingEmpty() throws {
        let app = sweepLaunch()
        try startSelecting(in: app)
        try assertSelectionChrome(app, count: 0)
        hold(1)
        attach(app.screenshot(), named: "library-selecting-none")
    }

    /// The shelf in selection mode with something actually picked.
    ///
    /// Inert chrome says nothing about what the chrome looks like when it is doing its job,
    /// and the walk in `ScreenshotTests` catches it inert. This one picks two covers first —
    /// two, so the count in the navigation bar is a plural in every language — and stays at
    /// the top of the shelf. What should be at the foot of the screen is one floating capsule
    /// with the shelf showing either side of it, where a grey slab used to sit on a glass
    /// pill.
    func testCaptureLibrarySelectingWithPicks() throws {
        let app = sweepLaunch()
        try startSelecting(in: app)
        try pickTwo(in: app)
        hold(1)
        attach(app.screenshot(), named: "library-selecting-picked")
    }

    /// Nothing picked, at the largest accessibility text size.
    ///
    /// The disabled row is the one that has the most to lose at this size: the labels are the
    /// widest they ever get *and* they are drawn in the dimmed style, so a `ViewThatFits`
    /// that chose the named branch one notch too optimistically clips text that is already
    /// hard to read.
    func testCaptureLibrarySelectingEmptyAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try startSelecting(in: app)
        try assertSelectionChrome(app, count: 0)
        hold(1)
        attach(app.screenshot(), named: "library-selecting-none-ax5")
    }

    /// Two picked, at the largest accessibility text size.
    ///
    /// **This is the capture the `ViewThatFits` in `BulkActionBar` exists for**, and the only
    /// thing that can settle it. Each action is named — *Add to…*, *Download*, *Mark as
    /// read* — wherever the width holds all three, and gives way to its glyph where it does
    /// not. A host test can prove the fallback is declared; it cannot prove which branch a
    /// phone at `accessibility-extra-extra-extra-large` takes, in a language whose words are
    /// longer again. Three glyphs in this frame means the fallback is doing real work and the
    /// names are still there for VoiceOver. Clipped text means the capsule is wrong.
    func testCaptureLibrarySelectingAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try startSelecting(in: app)
        try pickTwo(in: app)
        hold(1)
        attach(app.screenshot(), named: "library-selecting-ax5")
    }

    /// Reaches the shelf and puts it into selection mode, proving each step.
    ///
    /// `AuditWalk.showTheShelf(in:)` would do the first half and it skips rather than fails
    /// when the shelf never draws — and a skipped capture walk passes and photographs
    /// nothing, which `capture-ios.mjs` can only report as "attached nothing".
    func startSelecting(in app: XCUIApplication) throws {
        try XCTUnwrap(destination("Library", in: app), "The shell offers no Library tab.").tap()
        XCTAssertTrue(
            app.scrollViews.firstMatch.waitForExistence(timeout: 10),
            "The Library tab drew no shelf to select on."
        )
        try XCTUnwrap(hittable("Select", in: app), "The library toolbar offers no Select.").tap()
        XCTAssertTrue(
            app.buttons["Done"].waitForExistence(timeout: 5),
            "Tapping Select did not put the shelf into selection mode: no Done in the toolbar."
        )
    }

    /// Picks the first two covers on the shelf, and proves the shelf agrees.
    ///
    /// The covers are taken by position rather than by title: the corpus a device happens to
    /// hold decides the titles, and this walk is about the chrome rather than about which
    /// publication is in it. ``XCTestCase/realCovers(in:)`` is what makes "by position" safe
    /// — it filters on a format the spoken label carries, which no notice control does.
    func pickTwo(in app: XCUIApplication) throws {
        let covers = realCovers(in: app)
        XCTAssertGreaterThanOrEqual(
            covers.count,
            2,
            "The shelf offered fewer than two covers, so the capsule would be photographed "
                + "inert under a filename saying otherwise. On screen: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        for cover in covers.prefix(2) { cover.tap() }
        try assertSelectionChrome(app, count: 2)
    }

    /// That the chrome this change is about is on screen, in the state the filename claims.
    ///
    /// Three reads, and each of them is one of the three parts §3b.1 to §3b.4 moved:
    /// the count is the navigation title, the way out is the toolbar's trailing item, and
    /// the actions are present whether or not anything is picked. The count is the one that
    /// makes a picture of two picks distinguishable from a picture of none — everything else
    /// about the two frames is identical.
    func assertSelectionChrome(_ app: XCUIApplication, count: Int) throws {
        let title = "\(count) selected"
        XCTAssertTrue(
            app.navigationBars.staticTexts[title].waitForExistence(timeout: 5),
            "The navigation bar does not read “\(title)”. It reads: "
                + "\(app.navigationBars.staticTexts.allElementsBoundByIndex.map(\.label))"
        )
        XCTAssertTrue(app.buttons["Done"].exists, "The mode offers no way out.")
        // `Label` keeps its title as its accessibility label whichever branch of the
        // `ViewThatFits` drew it, so this holds at every text size — which is also the
        // §3b.5 claim, checked here because these are the only walks that see the capsule.
        for action in ["Add to…", "Download", "Mark as read"] {
            XCTAssertTrue(
                app.buttons[action].exists,
                "The action capsule offers no \(action), so it is not on screen."
            )
        }
    }
}
