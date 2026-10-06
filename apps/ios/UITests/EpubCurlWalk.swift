import XCTest

/// The page curl over **reflowable text**, which is task 8.12 and closes
/// `reader-theming-and-page-transitions` 4.3b.
///
/// `CurlWalk.swift` photographs the same roll over a comic and carries the long argument this
/// walk inherits: **a curl at rest is a page.** Every settled reader frame would look the same
/// whether the roll ran, ran backwards, or drew the wrong sheet, so what verifies a curl is a
/// frame taken while the fold is somewhere in the middle of the screen. XCUITest has no
/// primitive that leaves a touch down across a screenshot, so that frame comes from a screen
/// recording taken around ``testCaptureEpubCurlTurnedByATap`` — the same method and the same
/// command as the comic walk's, written down in this walk's README.
///
/// What this file adds to the comic walk is the thing 4.3b was about: the sheet is a
/// **raster**, not a decoded page. `ReflowableCurl.swift` photographs the outgoing page,
/// raises the shader over it at a progress of zero, moves the navigator underneath, and
/// photographs what arrived. If any of that is wrong the settled frame below is wrong in a way
/// a reader would see at once — the book on the wrong page, a blank sheet, or the chrome
/// baked into the picture — which is what makes a settled frame worth taking here and not
/// worth taking for the comic.
@MainActor
final class EpubCurlWalkTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A reflowable book, turned by a tap, in Curl.
    ///
    /// The frame this leaves is the page after the roll. The roll itself is in the recording.
    func testCaptureEpubCurlTurnedByATap() throws {
        let app = sweepLaunch()
        try openCurlingBook(in: app)
        // The trailing third, which `page-transitions` gives to the next page.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        hold(2)
        shutter(app, named: "ios-epub-curl-tapped")
    }

    /// Opens a reflowable book and puts it in Curl, proving the mode took.
    ///
    /// Through the app's own picker rather than an injected preference, for the reason
    /// `CurlWalk.openCurlingComic` gives: the transition is one field of a per-shelf
    /// `ShelfSettings` inside the `app.storyarc.themes` blob, which a test bundle that cannot
    /// see `StoryArcCore` would have to hand-encode.
    private func openCurlingBook(in app: XCUIApplication) throws {
        try openTheLongField(in: app)
        try openCurlRow(in: app)
        let curl = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Curl")).firstMatch
        guard curl.waitForExistence(timeout: 8) else {
            // Not a silent skip. Before 8.12 the picker listed Curl over reflowable text and
            // marked it unavailable, so a row that is missing *or* refused here is the whole
            // of what this walk exists to catch.
            XCTFail(
                "The Transition picker offers no Curl on a reflowable publication. Task 8.12 "
                    + "made `canCurlOverText` true for this reader. On screen: "
                    + "\(app.descendants(matching: .any).allElementsBoundByIndex.prefix(30).map(\.label))"
            )
            return
        }
        guard curl.isEnabled else {
            XCTFail("The Transition picker lists Curl on reflowable text but refuses it.")
            return
        }
        curl.tap()
        hold(1)
        // Three screens back out, and the page has to be unobscured before the tap means a
        // turn. Each is dismissed by its own control: a tap above a sheet lands on its dimmed
        // backdrop and leaves it up, which `CurlWalk` records photographing once.
        for _ in 0..<3 {
            guard let done = hittableRow("Done", in: app, timeout: 3) else { break }
            done.tap()
            hold(1)
        }
        XCTAssertTrue(
            app.buttons["Done"].waitForNonExistence(timeout: 8),
            "A sheet is still up, so a tap would land on it rather than on the page."
        )
        // The chrome has to have timed out before the tap, or the tap toggles it instead.
        hold(6)
    }

    /// Opens the one reflowable book this simulator reliably holds.
    ///
    /// *The Long Field*, and by that name, for `SweepEpubReaderTests.openReader`'s reason: a
    /// cover says `EPUB` whether the book reflows or is pre-paginated, and the app opens those
    /// in two different readers. Two of the corpus's four EPUBs are fixed-layout, so a walk
    /// that reached for "the first EPUB" would photograph the comic reader under a name that
    /// says the curl runs over text.
    ///
    /// A web view is what proves the reflowable reader arrived, which is the proof that sweep
    /// takes too.
    private func openTheLongField(in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        let wanted = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "The Long Field"))
        var cover: XCUIElement?
        for _ in 0..<8 where cover == nil {
            cover = wanted.allElementsBoundByIndex.first(where: \.isHittable)
            if cover == nil { app.swipeUp() }
        }
        try XCTSkipUnless(cover != nil, "This device's shelf never showed “The Long Field”.")
        cover?.tap()

        guard app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 8),
              let action = app.buttons.matching(opensAPublication)
                  .allElementsBoundByIndex.first(where: \.isHittable)
        else { throw XCTSkip("“The Long Field”'s page offered no hittable way to open it.") }
        action.tap()

        XCTAssertTrue(
            app.webViews.firstMatch.waitForExistence(timeout: 20),
            "Opening “The Long Field” reached no web view, so it is not the reflowable reader."
        )
        hold(4)
    }

    /// Opens the menu and reaches the Page turn row.
    ///
    /// The sheet opens at its medium detent, where *Page turn* is below the fold and absent
    /// from the tree rather than merely off screen — `SweepEpubReaderTests.openMenu` records
    /// the four walks that reported a missing row on a menu one detent away from having it.
    /// Reaches the page-turn rows and taps Curl.
    ///
    /// **Three screens deep, and that is the reflowable reader's own shape.** The comic
    /// reader puts *Page turn* in its menu; here it is a section of the axes screen, behind
    /// *Reading themes* and then *Customise*. `SweepEpubReaderTests.openMenu` and `openAxes`
    /// record why each hop needs a scroll loop rather than one swipe: a row below the fold of
    /// a sheet is absent from the tree, not merely off screen, and both walks reported a
    /// missing row on a sheet one detent away from having it.
    ///
    /// The rows are not a picker. *Page turn* is a heading and each mode is a button under
    /// it, so Curl is tapped directly once the section is on screen.
    private func openCurlRow(in app: XCUIApplication) throws {
        try XCTUnwrap(revealed("Menu", in: app), "The reader revealed no menu to open.").tap()
        for _ in 0..<5 where hittableRow("Reading themes", in: app, timeout: 1) == nil {
            app.swipeUp()
            hold(0.7)
        }
        try XCTUnwrap(
            hittableRow("Reading themes", in: app),
            "The menu offers no reading-themes row, at either detent."
        ).tap()

        for _ in 0..<6 where hittableRow("Customise", in: app, timeout: 1) == nil {
            app.swipeUp()
            hold(0.5)
        }
        try XCTUnwrap(
            hittableRow("Customise", in: app),
            "The theme sheet offers no Customise, scrolled to its foot."
        ).tap()

        for _ in 0..<10 where hittableRow("Curl", in: app, timeout: 1) == nil {
            app.swipeUp()
            hold(0.5)
        }
    }
}
