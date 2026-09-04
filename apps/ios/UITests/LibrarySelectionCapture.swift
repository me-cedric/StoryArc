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
        // The other end of the boundary the German walk pins. In English both names fit, so
        // *Download* carries a title and is far wider than the overflow's pure glyph. Asserted
        // here rather than in `assertSelectionChrome`, because that helper runs at the
        // accessibility sizes too, where this is deliberately false.
        let download = app.buttons["Download"].frame.width
        let more = app.buttons["More actions"].frame.width
        XCTAssertGreaterThan(
            download,
            more * 1.6,
            "English draws *Download* as a bare glyph (\(download) pt against the overflow's "
                + "\(more) pt), so a phone is taking a narrower tier than the frames show."
        )
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
        try assertSelectionChrome(app, count: 0, namingMarkRead: false)
        hold(1)
        attach(app.screenshot(), named: "library-selecting-none-ax5")
    }

    /// Two picked, at the largest accessibility text size.
    ///
    /// **This is the capture the `ViewThatFits` in `BulkActionBar` exists for**, and the only
    /// thing that can settle it. The capsule degrades by control, so this is the tier where
    /// only *Download* and the overflow survive — both glyphs the platform has established —
    /// and mark-as-read's name is drawn inside the menu instead. A host test can prove the
    /// tiers are declared; it cannot prove which one a phone at
    /// `accessibility-extra-extra-extra-large` takes, in a language whose words are longer
    /// again. Two glyphs in this frame means the floor is doing real work and every name is
    /// still there for VoiceOver. Clipped text means the capsule is wrong.
    func testCaptureLibrarySelectingAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try startSelecting(in: app)
        try pickTwo(in: app, namingMarkRead: false)
        hold(1)
        attach(app.screenshot(), named: "library-selecting-ax5")
    }

    /// Reaches the shelf and puts it into selection mode, proving each step.
    ///
    /// `AuditWalk.showTheShelf(in:)` would do the first half and it skips rather than fails
    /// when the shelf never draws — and a skipped capture walk passes and photographs
    /// nothing, which `capture-ios.mjs` can only report as "attached nothing".
    /// The inert capsule is measurably dimmer than the live one, on a device.
    ///
    /// **A ratio, not a difference, because `.opacity` is a multiplication.** Compositing at
    /// `inertOpacity` gives `pixel = α·ink + (1 − α)·background`, so every pixel's distance
    /// from the background is scaled by exactly α — and the ratio of the two ink masses lands
    /// on the opacity itself, near 0.4, wherever the glass happens to be and whatever cover is
    /// passing under it. That is what makes one band work in both appearances and at both text
    /// sizes without a per-appearance constant.
    ///
    /// The band is two-sided on purpose. Above 0.75 the inert control is not dimmed — and the
    /// state this reproduces is not hypothetical, it is what shipped: the two states measured
    /// **identical**, worst channel delta 0 to 2 of 255, so a regression returns 1.000 with
    /// twenty-five points of headroom below the ceiling. Below 0.10 it has effectively been
    /// hidden, which `§3b.4` refuses just as firmly: the actions are "present and inert rather
    /// than absent", because a capsule arriving on the first pick is chrome appearing under a
    /// thumb mid-tap.
    ///
    /// `pickTwo` ends by proving the navigation bar reads *2 selected*, which is the control
    /// that the two measurements are of two different states rather than the same one twice.
    ///
    /// **Measured on 2026-09-04**, `StoryArc-iPhone17Pro`, light: ink mass 18.77 inert against
    /// 45.45 live, a ratio of **0.4129** where the opacity is 0.4 — the constant recovered from
    /// the device to within three per cent, which is the evidence that the model above is the
    /// right model rather than a threshold that happens to hold. Dark passes the same band.
    /// With the `.opacity` line deleted the ratio is **1.0** and the two ink masses are
    /// identical to fourteen digits, which is precisely the state that shipped.
    func testTheInertCapsuleIsDimmerThanTheLiveOne() throws {
        let app = sweepLaunch()
        try startSelecting(in: app)
        let named = ["Download", "Mark as read", "More actions"]
        let inert = named.map { CapsuleInk.mass(of: app.buttons[$0]) }
        try pickTwo(in: app)
        let live = named.map { CapsuleInk.mass(of: app.buttons[$0]) }

        for (index, action) in named.enumerated() {
            XCTAssertGreaterThan(
                live[index],
                0,
                "\(action) drew no ink at all when live, so this measures nothing."
            )
            let ratio = inert[index] / live[index]
            XCTAssertLessThan(
                ratio,
                0.75,
                "\(action) is drawn the same inert as live — ratio \(ratio), "
                    + "ink \(inert[index]) vs \(live[index]). `.disabled` cannot dim it: "
                    + "`storyArcGlassText` sets a foreground style after it and wins."
            )
            XCTAssertGreaterThan(
                ratio,
                0.10,
                "\(action) has all but vanished when inert — ratio \(ratio). The actions are "
                    + "shown and inert rather than absent, so a reader can see what the mode is for."
            )
        }
    }

    func startSelecting(
        in app: XCUIApplication,
        library: String = "Library",
        select: String = "Select",
        done: String = "Done"
    ) throws {
        try XCTUnwrap(destination(library, in: app), "The shell offers no \(library) tab.").tap()
        XCTAssertTrue(
            app.scrollViews.firstMatch.waitForExistence(timeout: 10),
            "The \(library) tab drew no shelf to select on."
        )
        try XCTUnwrap(hittable(select, in: app), "The library toolbar offers no \(select).").tap()
        XCTAssertTrue(
            app.buttons[done].waitForExistence(timeout: 5),
            "Tapping \(select) did not put the shelf into selection mode: no \(done)."
        )
    }

    /// The capsule in **German**, which is the language the tiers exist for.
    ///
    /// *Als gelesen markieren* is 21 characters against *Mark as read*'s 12, and
    /// *Herunterladen* is 13 against *Download*'s 8. So German is the case that decides how
    /// many names the row can draw, and a design that fits in English and not in German ships
    /// broken to a German reader — which is why shortening the English copy was rejected
    /// outright rather than tried.
    ///
    /// **Existence is not the assertion, and that took a verification pass to notice.** A
    /// `Label` keeps its title as its accessibility label whatever the label style draws, so
    /// `app.buttons["Als gelesen markieren"].exists` is true at every tier and cannot tell
    /// tier 1 from tier 2 — the one distinction this walk is for. What separates them is
    /// **width**: at tier 2 *Download* is drawn icon-only, so its frame is about as wide as
    /// the overflow's pure glyph; at tier 1 it carries a title and is far wider. Comparing the
    /// two controls rather than either against a constant is what keeps this true at any text
    /// size and on any device, since both grow together.
    func testCaptureLibrarySelectingInGerman() throws {
        let app = sweepLaunch(language: "de")
        try startSelecting(in: app, library: "Bibliothek", select: "Auswählen", done: "Fertig")
        let covers = realCovers(in: app)
        XCTAssertGreaterThanOrEqual(covers.count, 2, "The shelf offered fewer than two covers.")
        for cover in covers.prefix(2) { cover.tap() }
        XCTAssertTrue(
            app.buttons["Als gelesen markieren"].waitForExistence(timeout: 5),
            "The capsule draws no named action in German. On screen: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        let download = app.buttons["Herunterladen"].frame.width
        let more = app.buttons["Weitere Aktionen"].frame.width
        let markRead = app.buttons["Als gelesen markieren"].frame.width
        XCTAssertLessThan(
            download,
            more * 1.6,
            "German draws *Herunterladen* as well (\(download) pt against the overflow's "
                + "\(more) pt), so this is tier 1 and the German fallback is not being taken."
        )
        XCTAssertGreaterThan(
            markRead,
            more * 2,
            "German draws no name at all (\(markRead) pt against the overflow's \(more) pt), "
                + "so it has fallen past tier 2 to the glyph-only floor."
        )
        hold(1)
        attach(app.screenshot(), named: "library-selecting-picked-de")
    }

    /// Picks the first two covers on the shelf, and proves the shelf agrees.
    ///
    /// The covers are taken by position rather than by title: the corpus a device happens to
    /// hold decides the titles, and this walk is about the chrome rather than about which
    /// publication is in it. ``XCTestCase/realCovers(in:)`` is what makes "by position" safe
    /// — it filters on a format the spoken label carries, which no notice control does.
    func pickTwo(in app: XCUIApplication, namingMarkRead: Bool = true) throws {
        let covers = realCovers(in: app)
        XCTAssertGreaterThanOrEqual(
            covers.count,
            2,
            "The shelf offered fewer than two covers, so the capsule would be photographed "
                + "inert under a filename saying otherwise. On screen: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        for cover in covers.prefix(2) { cover.tap() }
        try assertSelectionChrome(app, count: 2, namingMarkRead: namingMarkRead)
    }

    /// That the chrome this change is about is on screen, in the state the filename claims.
    ///
    /// Three reads, and each of them is one of the three parts §3b.1 to §3b.4 moved:
    /// the count is the navigation title, the way out is the toolbar's trailing item, and
    /// the actions are present whether or not anything is picked. The count is the one that
    /// makes a picture of two picks distinguishable from a picture of none — everything else
    /// about the two frames is identical.
    func assertSelectionChrome(
        _ app: XCUIApplication,
        count: Int,
        namingMarkRead: Bool = true
    ) throws {
        let title = "\(count) selected"
        XCTAssertTrue(
            app.navigationBars.staticTexts[title].waitForExistence(timeout: 5),
            "The navigation bar does not read “\(title)”. It reads: "
                + "\(app.navigationBars.staticTexts.allElementsBoundByIndex.map(\.label))"
        )
        XCTAssertTrue(app.buttons["Done"].exists, "The mode offers no way out.")
        // `Label` keeps its title as its accessibility label whichever tier drew it, so these
        // two hold at every text size. *Add to…* is deliberately **not** here any more: it is
        // inside the overflow now, because `text.badge.plus` is not a glyph a reader can read
        // unaided and the action opens a chooser rather than doing something.
        for action in ["Download", "More actions"] {
            XCTAssertTrue(
                app.buttons[action].exists,
                "The action capsule offers no \(action), so it is not on screen."
            )
        }
        // **This is the assertion that pins the tier, and it is the one no host test can
        // make.** The capsule degrades by control: at the default size it draws
        // `⬇  ✓ Mark as read  ⋯`, and at the accessibility sizes the named button will not
        // fit beside the other two, so it gives way and the action lives in the overflow.
        // Asserting presence *and absence* is what stops the tier boundary drifting silently
        // — which is exactly what happened before, when three names never fit at any size and
        // every source-text guard still passed.
        XCTAssertEqual(
            app.buttons["Mark as read"].exists,
            namingMarkRead,
            namingMarkRead
                ? "The capsule draws no named action at this size, so it is three bare glyphs."
                : "The named action still fits at the largest text size, so this walk is "
                    + "photographing the wrong tier."
        )
    }
}
