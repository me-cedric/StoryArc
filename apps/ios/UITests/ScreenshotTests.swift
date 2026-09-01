import XCTest

/// Photographs a screen, so that `AGENTS.md` section 6's visual proof is repeatable.
///
/// Android has `pnpm capture:android`, which walks to a named screen, sets the text size and
/// the appearance, photographs it, and puts the device back. iOS had `xcrun simctl io booted
/// screenshot`, which photographs whatever happens to be in front of it — so every iOS proof
/// this project has taken involved a person driving the simulator by hand, and the one time
/// that was automated with synthetic clicks the coordinates missed the tab bar and produced
/// a picture of Home labelled *Downloads*.
///
/// A UI test already knows how to reach a screen: `AuditWalk.swift` owns that, and the audit
/// suite has been walking these same destinations for a day. Reusing it means the capture
/// cannot drift away from the walk that the audit and the crash checks use.
///
/// The screenshots come out of the result bundle:
/// ```
/// xcodebuild test -project apps/ios/StoryArc.xcodeproj -scheme StoryArc \
///   -destination 'platform=iOS Simulator,name=StoryArc-iPhone17Pro' \
///   -only-testing:StoryArcUITests/ScreenshotTests -resultBundlePath /tmp/shots.xcresult
/// xcrun xcresulttool export attachments --path /tmp/shots.xcresult --output-path /tmp/shots
/// ```
///
/// `.keepAlways` matters: an attachment on a passing test is deleted by default, and a
/// capture suite whose every test passes would produce nothing at all.
@MainActor
final class ScreenshotTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCaptureDownloads() throws {
        let app = launch()
        try XCTUnwrap(destination("Downloads", in: app)).tap()
        // The shelf, not the tab: tapping a tab is instant and decoding covers is not, and a
        // screenshot taken between the two shows an empty grid on every build alike — which
        // would make a before and an after identical for a reason that has nothing to do
        // with the change.
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "downloads")
    }

    func testCaptureHome() throws {
        let app = launch()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "home")
    }

    func testCaptureLibrary() throws {
        let app = launch()
        try XCTUnwrap(destination("Library", in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "library")
    }

    /// The library at the largest accessibility text size.
    ///
    /// Android's filter chip row ran off the window at `font_scale 2.0` and had to learn to
    /// wrap. The question this answers is whether iOS's equivalent has the same defect, and
    /// it is a fair question because both platforms draw the same three controls — narrow to
    /// what is on this device, choose an order, filter.
    ///
    /// They do not draw them the same way, which is the answer: iOS puts them in a toolbar
    /// as icons, and an icon does not grow with the reader's text. The picture is what says
    /// so, because a claim that a row cannot overflow is worth exactly as much as the
    /// largest text size somebody actually pointed at it.
    func testCaptureLibraryAtLargestText() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try XCTUnwrap(destination("Library", in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "library-ax5")
    }

    /// The library scrolled to its end, which is the only place the floating tab bar's
    /// question can be answered.
    ///
    /// **A shelf photographed at the top cannot tell a defect from the design.** Content
    /// passing *under* a Liquid Glass bar is what the material is for; what would be a defect
    /// is a last row that can never be scrolled clear of it, and only the end of the scroll
    /// shows which of the two this is. `docs/designs/ui-revamp-2026-08.md` §7.5 recorded
    /// captions rendering behind a floating pill on 2026-08-30, when there was no tab bar for
    /// the content to inset against; this is the capture that says whether anything is still
    /// owed now that there is one.
    func testCaptureLibraryAtTheEnd() throws {
        let app = launch()
        try XCTUnwrap(destination("Library", in: app)).tap()
        let shelf = app.scrollViews.firstMatch
        _ = shelf.waitForExistence(timeout: 10)
        // Swiped rather than scrolled to an element: the last cell is what is in question, so
        // asking XCUITest to reveal it would be asking the framework the thing being measured.
        for _ in 0..<8 { shelf.swipeUp() }
        settle(1)
        attach(app.screenshot(), named: "library-end")
    }

    /// The search destination, which is the whole point of `quiet-shell-and-search`.
    ///
    /// **This capture could not have been written before the change.** Search was
    /// `Tab(role: .search)`, which is not a destination: tapping it morphed the bar into a
    /// field in place, so there was no screen to reach and nothing to photograph but a bar
    /// in two states. The tap below works because search is now a tab like its neighbours,
    /// and `destination(_:in:)` finds it the same way it finds Library and Downloads.
    ///
    /// Photographed at rest, with nothing typed, because that is what the change added: the
    /// suggestions, the recent searches, and the scope. What a *query* finds shipped already
    /// and is asserted in `LibrarySearchTests`.
    func testCaptureSearch() throws {
        let app = launch()
        try XCTUnwrap(destination("Search", in: app)).tap()
        // The shelf's own wait, and for the shelf's own reason: tapping a tab is instant and
        // decoding a run of covers is not, so a screenshot taken between the two shows empty
        // sections on every build alike — which would make a before and an after identical
        // for a reason that has nothing to do with the change.
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "search")
    }

    /// The search destination at the largest accessibility text size.
    ///
    /// Three section headings, a run of covers under each, and a scope control. The heading
    /// wording is the risk — *Next in a series you have read* is a sentence rather than a
    /// word, and French's is longer again — and a claim that it wraps rather than clipping is
    /// worth exactly as much as the largest text size somebody actually pointed at it.
    func testCaptureSearchAtLargestText() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try XCTUnwrap(destination("Search", in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "search-ax5")
    }

    /// About, which is where a reader who dismissed the what’s-new sheet too fast finds it
    /// again — `settings-and-about`: "it is reachable from the About screen, along with the
    /// entries for earlier versions".
    ///
    /// Photographed before that row existed as well as after, because a row added to a list
    /// is exactly the change a picture of the finished screen cannot prove on its own.
    func testCaptureAbout() throws {
        let app = launch()
        try openAbout(in: app)
        attach(app.screenshot(), named: "about")
    }

    /// What’s new, reached the way the sheet is *not* — from About, which the spec requires
    /// "does not change what the app considers seen".
    func testCaptureWhatsNewFromAbout() throws {
        let app = launch()
        try openAbout(in: app)
        try XCTUnwrap(control("What\u{2019}s new", in: app), "About has no What’s new row.").tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 5)
        attach(app.screenshot(), named: "whats-new-from-about")
    }

    /// The sheet itself, on the launch after an update.
    ///
    /// **The version it has already been told about is injected as a launch argument, not by
    /// a hook in the app.** `UserDefaults`’s argument domain outranks the standard one, so
    /// passing `-app.storyarc.whatsNewSeen` makes `WhatsNewStore` read an older version and
    /// the shell take the branch it takes on a real update — the same code, on the same
    /// path, with nothing test-only in it. The content-size argument two lines up is the
    /// same mechanism.
    func testCaptureWhatsNew() throws {
        attach(try whatsNewSheet(contentSize: nil), named: "whats-new")
    }

    /// The same sheet at the largest accessibility text size. `settings-and-about`: "every
    /// entry’s heading and sentence are readable in full, the screen scrolls if it must,
    /// and the dismissing action stays reachable without scrolling past the content".
    func testCaptureWhatsNewAtLargestText() throws {
        attach(
            try whatsNewSheet(contentSize: "UICTContentSizeCategoryAccessibilityXXXL"),
            named: "whats-new-ax5"
        )
    }

    private func whatsNewSheet(contentSize: String?) throws -> XCUIScreenshot {
        let app = XCUIApplication()
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launchArguments += ["-app.storyarc.whatsNewSeen", "0.0.1"]
        app.launch()
        // The sheet identifies itself before anything is photographed, for the reason
        // `AuditWalk` gives at length: a capture that can silently photograph the screen
        // behind the one it names is worth less than no capture.
        XCTAssertTrue(
            app.buttons["Continue"].waitForExistence(timeout: 10),
            "No what’s-new sheet appeared on the launch after an update."
        )
        // And `isHittable`, not existence alone, because existence was the whole assertion
        // and it is not the requirement. `settings-and-about` asks that at the largest
        // accessibility text size "the dismissing action stays reachable **without scrolling
        // past the content**" — and an `XCUIElement` below the visible edge still *exists*,
        // so the check passed in exactly the state it was written to catch. This is the only
        // largest-text assertion iOS has for this screen; Android's three Robolectric cases
        // in `WhatsNewLayoutTest` measure it properly, and until iOS has an equivalent this
        // line is carrying the whole platform.
        XCTAssertTrue(
            app.buttons["Continue"].isHittable,
            "Continue exists but is not reachable — it is off-screen at this text size, "
            + "which is the failure the requirement names rather than a passing capture."
        )
        return app.screenshot()
    }

    /// Home → Settings → About. The rows are `NavigationLink`s in a `List`, which is why this
    /// asks ``control(_:in:)`` rather than for a button.
    private func openAbout(in app: XCUIApplication) throws {
        try XCTUnwrap(control("Settings", in: app), "Home has no way into Settings.").tap()
        try XCTUnwrap(control("About", in: app), "Settings has no About row.").tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 5)
    }

    /// The theme sheet and its six presets, which `reader-theming-and-page-transitions`
    /// task 7.4 asks for and which has been recorded as impossible on this platform.
    ///
    /// That task said "iOS cannot be captured: the simulator accepts no injected input, so the
    /// reader cannot be reached to open the sheet", and `apps/ios/README.md` records the three
    /// approaches that were tried. Input was never the obstacle: a UI test injects through
    /// XCUITest rather than through the Simulator's window.
    ///
    /// What the blocker was narrowed to next — "the EPUB reader does not reach a state with
    /// its own controls" — does not follow either, because that run never established which
    /// reader it was in. It asked for an EPUB, and a **fixed-layout** EPUB satisfies that and
    /// is not opened in the reflowable reader at all. Whether the reflowable reader has a
    /// problem of its own is a thing no run has measured yet.
    ///
    /// The sheet lives in the **EPUB** reader, not the comic reader, because a reading theme
    /// applies to reflowable text. Its control is labelled *Reading* — `theme.title` in
    /// `EpubReaderFeature`. A fixed-layout EPUB cannot be used for this, and the reason is
    /// one screen earlier than it looks: `Publication.isReflowable` is false for one, so the
    /// app opens it in the comic reader, where the reading themes have no control of their
    /// own. Asking the shelf for "an EPUB" is therefore not enough — see
    /// ``openTheEpubReader(in:)``, which is what made this capture possible.
    ///
    /// All six presets are in one shot deliberately, following the Android captures: the grid
    /// draws each preset in its own colours *and* its own typeface, and that is the thing worth
    /// proving. Six separate screenshots would prove less.
    func testCaptureThemeSheet() throws {
        try captureThemeSheet(contentSize: nil, named: "theme-sheet")
    }

    /// The same sheet at the largest accessibility text size, which is the half task 7.4 names
    /// separately — a specimen is a picture of a typeface in a card of fixed height, and that
    /// is exactly the shape that clips when the reader's type grows.
    func testCaptureThemeSheetAtLargestText() throws {
        try captureThemeSheet(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            named: "theme-sheet-largest"
        )
    }

    private func captureThemeSheet(contentSize: String?, named name: String) throws {
        let app = launch(contentSize: contentSize)
        // Waits for the control itself, not for `otherElements.firstMatch` — that exists on
        // every screen and returns instantly, so the first version of this walked on while
        // the publication page was still up, tapped its middle, and reported no theme sheet
        // on a screen that never had one. And it opens EPUBs until one of them lands in the
        // reflowable reader **with a page in it**, because a cover cannot say which of the
        // two readers it opens and the theme control is drawn over the loading spinner as
        // readily as over a book. A version that stopped at the first EPUB skipped every run
        // for a day. When no EPUB on the device gets there it still skips, and names every
        // one it tried and how far each got.
        try openTheEpubReader(in: app)
        // Two taps where there used to be one. `quiet-reader` moved the themes control off
        // the page and into the reader's menu, so reaching the sheet now means revealing
        // chrome and then choosing a row — and the centre tap is a `coordinate` because the
        // element under the middle of the page is the web view, whose own tap handling is the
        // reader's.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let menu = app.buttons["Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "the reader revealed no menu to open")
        menu.tap()
        let themes = app.buttons["Reading themes"]
        XCTAssertTrue(themes.waitForExistence(timeout: 5), "the menu offered no reading themes")
        themes.tap()
        // The sheet is a presentation; it animates up over the page.
        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Original")).firstMatch
            .waitForExistence(timeout: 5)
        attach(app.screenshot(), named: name)
    }

    /// The reflowable reader, photographed on arrival and again after a centre tap.
    ///
    /// `quiet-reader` cuts revealed chrome from three surfaces and about eleven controls to
    /// two — a way out and a way in — so the proof it owes under `AGENTS.md` section 6 is a
    /// picture of what the reader shows, before and after. Counting controls in a screenshot
    /// is exactly the comparison a source-level test cannot make.
    ///
    /// **Two shots, because a single tap proves nothing on its own.** The old reader drew its
    /// chrome on arrival (`isChromeVisible` started `true`), so a capture that tapped once
    /// photographed a *hidden* bar and made the before and the after identically empty — which
    /// is what the first version of this did, on both trees, and it looked like a successful
    /// comparison. Photographing arrival and the tap separately means whichever state carries
    /// the chrome is in the pair, and the pair also shows *when* it is drawn, which is itself
    /// part of what changed.
    ///
    /// The centre tap is a `coordinate` rather than a `tap()` on an element: the page fills
    /// the screen and the element under the middle of it is the web view, whose own tap
    /// handling is the reader's. Tapping the element would ask XCTest for a hit point and it
    /// may pick an edge, which is a page turn.
    func testCaptureReaderChrome() throws {
        let app = launch()
        try openTheEpubReader(in: app)
        attach(app.screenshot(), named: "reader-on-arrival")

        // Untouched, past the countdown. This is the frame that proves `comic-reader`'s
        // "they fade out again after 4 seconds of no interaction", and the order matters:
        // taken after the centre tap it proved nothing, because the tap had already hidden
        // the chrome. The reflowable reader only ever *toggled* until this change, so on
        // that reader an empty frame here is the whole fix.
        settle(6)
        attach(app.screenshot(), named: "reader-after-the-countdown")

        // And a tap brings them back. The centre tap is a `coordinate` rather than a
        // `tap()` on an element: the page fills the screen and the element under the middle
        // of it is the web view, whose own tap handling is the reader's. Tapping the element
        // would ask XCTest for a hit point and it may pick an edge, which is a page turn.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        settle(1)
        attach(app.screenshot(), named: "reader-after-centre-tap")
    }

    /// The comic reader's chrome, over a page dark enough to see the glass through.
    ///
    /// The reflowable capture above is honest and it cannot prove the *material*: the Paper
    /// theme is cream, so glass over it is cream, and a control that had been flattened into
    /// an opaque pill looks nearly the same as one that has not. The owner's own example —
    /// Photos' overlay — reads as glass because the content behind it is dark.
    ///
    /// The comic fixtures are solid procedurally-coloured pages, so this puts the same two
    /// controls over a saturated one. If the glass is picking up the page, the capsules carry
    /// its colour; if a `.tint` has come back, they are white again.
    ///
    /// `GlassIsUntintedTests` is the guard; this is the picture that made the defect visible
    /// in the first place.
    func testCaptureComicReaderChrome() throws {
        let app = launch()
        try showTheShelf(in: app)
        let covers = coversOnScreen(in: app, ofFormat: "CBZ")
        try XCTSkipIf(covers.isEmpty, "This device's library showed no CBZ cover to open.")
        covers[0].tap()

        guard app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 5),
              let action = app.buttons.matching(opensAPublication)
                  .allElementsBoundByIndex.first(where: \.isHittable)
        else { throw XCTSkip("The publication page offered no hittable way to open it.") }
        action.tap()

        // The reader draws its chrome on arrival, so there is nothing to tap for.
        settle(2)
        attach(app.screenshot(), named: "comic-reader-chrome")
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

    // Internal, not private: `private` is file-scoped, and the captures for the
    // skipped-publications notice live in `SkippedNoticeCapture.swift` — this file is at the
    // length the linter warns at.
    func attach(_ shot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
