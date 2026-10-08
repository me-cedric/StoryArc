import XCTest

/// The comic reader and everything behind its two buttons.
///
/// `quiet-reader` cut this reader's revealed chrome from eleven controls to two — a way out
/// and a way in — and moved the other nine into a menu. `ScreenshotTests` photographs the two
/// buttons over a page. **Nothing has ever photographed what is behind the second one**, which
/// is where the transition picker, the fit picker, the reading direction, the orientation
/// lock, the page slider, the thumbnail browser and the image adjustments all went.
///
/// So the design question this suite exists to put in front of a reviewer is the one the
/// change made and no picture has answered: nine controls in a half-height sheet, each stating
/// its own name and its own value — is that better than nine glyphs over the artwork?
@MainActor
final class SweepComicReaderTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The page with nothing on it, four seconds after arrival.
    ///
    /// `comic-reader`: the controls "fade out again after 4 seconds of no interaction". This
    /// is the state a reader spends the whole publication in, and the artwork-is-the-interface
    /// claim stands or falls on it.
    func testCaptureComicPage() throws {
        let app = sweepLaunch()
        try openComic(in: app)
        hold(6)
        shutter(app, named: "comic-reader-page")
    }

    /// The chrome, revealed by a centre tap.
    ///
    /// The centre tap is a `coordinate` rather than a `tap()` on an element: the page fills
    /// the screen and the element under the middle of it is the page view, whose own tap
    /// handling is the reader's. Tapping the element would ask XCTest for a hit point and it
    /// may pick an edge, which is a page turn.
    func testCaptureComicChrome() throws {
        let app = sweepLaunch()
        try openComic(in: app)
        try revealChrome(in: app)
        hold(1)
        // Not `comic-reader-chrome`: `ScreenshotTests.testCaptureComicReaderChrome` already
        // files that name, photographing the chrome the reader draws *on arrival*. This is
        // the chrome brought back after the countdown has taken it, which is a different
        // state — and two walks writing one filename means whichever ran last is the picture.
        shutter(app, named: "comic-reader-chrome-revealed")
    }

    /// The menu: nine controls as named rows, at the sheet's medium detent.
    func testCaptureComicMenu() throws {
        let app = sweepLaunch()
        try openComic(in: app)
        try openMenu(in: app)
        hold(1)
        shutter(app, named: "comic-reader-menu")
    }

    /// The menu at its large detent, which is the only way to see all of it at once.
    func testCaptureComicMenuExpanded() throws {
        let app = sweepLaunch()
        try openComic(in: app)
        try openMenu(in: app)
        app.swipeUp()
        hold(1)
        shutter(app, named: "comic-reader-menu-expanded")
    }

    /// The fit picker, open.
    ///
    /// Four ways to size a page — Screen, Width, Height, 1:1 — behind a menu-styled row that
    /// states the current one. The segmented control it replaced is in
    /// `connected-button-groups-2026-09-01`; this is what took its place and it has no picture.
    func testCaptureComicFitPicker() throws {
        let app = sweepLaunch()
        try openComic(in: app)
        try openMenu(in: app)
        try XCTUnwrap(hittableRow("Fit", in: app), "The reader menu offers no Fit row.").tap()
        // **This tap used to reach nothing, and the row was the reason rather than the tap.**
        // `Fit` was a menu-styled `Picker`, whose button is its *trailing value alone*, so
        // `tap()` — which lands on the element's centre — pressed the dead space between the
        // name and the value. Established on a booted iPhone 17 Pro on 2026-09-04: a tap on
        // `Screen ⌄` opened all four options, a tap on the word `Fit` opened nothing, and so
        // did a tap on the middle of the row. It is a `Menu` now, like `Transition` beside it,
        // and opens from anywhere on the row — see `ReaderMenuHitAreaTests`.
        //
        // Asked of any element rather than of a button: what the platform calls the rows of an
        // open menu is not this file's business.
        let width = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Width")).firstMatch
        XCTAssertTrue(
            width.waitForExistence(timeout: 8),
            "The Fit row opened no menu. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label)). Cells: "
                + "\(app.cells.allElementsBoundByIndex.prefix(10).map(\.label)). Texts: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        hold(0.75)
        shutter(app, named: "comic-reader-fit-picker")
    }

    /// The transition picker, open, with the reasons under the modes this device refuses.
    ///
    /// `page-transitions`: a mode that cannot run is "shown unavailable with a one-line
    /// reason, never silently absent" — and Curl is the exception that is absent, with its
    /// own sentence. A menu rather than a picker exists precisely so a row can be disabled
    /// and carry a reason, and no picture of that has been taken.
    func testCaptureComicTransitionPicker() throws {
        let app = sweepLaunch()
        try openComic(in: app)
        try openMenu(in: app)
        try XCTUnwrap(rowInTheMenu("Page turn", in: app), "The menu offers no Page turn row.").tap()
        // A `Menu` here rather than a `Picker`, precisely so a row can be disabled and carry
        // a reason — so this one does open a menu. Asked of any element for the same reason
        // the fit picker is: what the platform calls a menu row is not this file's business.
        let slide = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Slide")).firstMatch
        XCTAssertTrue(
            slide.waitForExistence(timeout: 8),
            "The Page turn row opened no picker. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        hold(0.75)
        shutter(app, named: "comic-reader-transition-picker")
    }

    /// The thumbnail browser: every page, with the current one marked.
    func testCaptureComicThumbnails() throws {
        let app = sweepLaunch()
        try openComic(in: app)
        try openMenu(in: app)
        // The menu sheet slides up. A tap while it moves lands on the row below Contents.
        hold(1)
        try XCTUnwrap(hittableRow("Contents", in: app), "The menu offers no Contents row.").tap()
        XCTAssertTrue(
            app.buttons["Page 1"].waitForExistence(timeout: 8)
                || app.staticTexts["Pages"].waitForExistence(timeout: 3),
            "Contents opened no thumbnail strip. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        hold(2)
        shutter(app, named: "comic-reader-thumbnails")
    }

    /// The page browser on a comic with chapter bookmarks: the chapter name above the
    /// carousel, the chapter badges, the page numbers and the ticks on the page slider.
    func testCaptureComicPageBrowser() throws {
        let app = sweepLaunch(freshShelfSettings: true)
        try openPublication(named: "Quiet Machines", in: app)
        try openMenu(in: app)
        // The menu sheet slides up. A tap while it moves lands on the row below Contents.
        hold(1)
        let second = try openPageBrowser(in: app)
        hold(2)
        shutter(app, named: "comic-reader-page-browser")
        second.swipeLeft(velocity: .slow)
        hold(2)
        shutter(app, named: "comic-reader-page-browser-swiped")
    }

    /// The page browser, in dark. `page-browser-carousel` 3.2.
    func testCaptureComicPageBrowserDark() throws {
        let app = sweepLaunch(appearance: "dark", freshShelfSettings: true)
        try openPublication(named: "Quiet Machines", in: app)
        try openMenu(in: app)
        hold(1)
        try openPageBrowser(in: app)
        hold(2)
        shutter(app, named: "comic-reader-page-browser-dark")
    }

    /// The page browser on a right-to-left comic: the carousel and its slider ticks mirror.
    /// `page-browser-carousel` 3.2.
    func testCaptureComicPageBrowserRightToLeft() throws {
        let app = sweepLaunch(freshShelfSettings: true)
        try openPublication(named: "Quiet Machines", in: app)
        try openMenu(in: app)
        // The direction row is in the Settings section, below the fold at `.medium`.
        app.swipeUp()
        try XCTUnwrap(
            hittableRow("Reading direction", in: app), "The menu offers no Reading direction row."
        ).tap()
        let rightToLeft = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Right to left")).firstMatch
        XCTAssertTrue(rightToLeft.waitForExistence(timeout: 8), "The Reading direction row opened no picker.")
        rightToLeft.tap()
        hold(1)
        try openPageBrowser(in: app, rightToLeft: true)
        hold(2)
        shutter(app, named: "comic-reader-page-browser-rtl")
    }

    /// The image adjustments sheet — brightness, contrast, sharpness, greyscale, invert, and
    /// the border trim — which is the one surface in the app that changes the artwork itself.
    func testCaptureComicAdjustments() throws {
        let app = sweepLaunch()
        try openComic(in: app)
        try openMenu(in: app)
        try XCTUnwrap(hittableRow("Appearance", in: app), "The menu offers no Appearance row.").tap()
        XCTAssertTrue(
            app.staticTexts["Brightness"].waitForExistence(timeout: 5)
                || app.staticTexts["Image adjustments"].waitForExistence(timeout: 3),
            "Appearance opened no adjustments. Texts: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        hold(1)
        shutter(app, named: "comic-reader-adjustments")
    }

    /// A PDF's *Find* sheet, which is a reader surface only one format has.
    ///
    /// `Field Notes.pdf` carries a real text layer, so the marks and search tabs are drawn
    /// rather than hidden — `ebook-reader` hides a text-dependent control rather than
    /// disabling it, so on a scan this row is simply not there.
    func testCapturePdfTextSheet() throws {
        let app = sweepLaunch()
        try openPublication(named: "Field Notes", in: app)
        try openMenu(in: app)
        guard let search = hittableRow("Search", in: app) else {
            throw XCTSkip(
                "This PDF's menu offers no Search row, so it carries no text layer. Buttons: "
                    + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
            )
        }
        search.tap()
        hold(1.5)
        shutter(app, named: "pdf-find-sheet")
    }

    // MARK: - The walk

    /// Opens a comic with real artwork on its pages.
    ///
    /// `Fine Print` is 2400×3600 ruled pages rather than flat colour, so the chrome is
    /// photographed over something a reviewer can judge a material against — flat orange
    /// behind a glass capsule says less than a page with detail in it does.
    private func openComic(in app: XCUIApplication) throws {
        try openPublication(named: "Fine Print", in: app)
    }

    /// Opens one publication by name and proves a reader is up.
    ///
    /// The page view is the landmark. Waiting on the close button instead would pass on the
    /// publication page, which has a navigation-bar back button of its own.
    private func openPublication(named title: String, in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        var found: XCUIElement?
        for _ in 0..<8 where found == nil {
            found = wanted.allElementsBoundByIndex.first(where: \.isHittable)
            if found == nil { app.swipeUp() }
        }
        // 21.1-ios: at the largest accessibility text size a row is 147 pt tall, and a cover
        // can settle with most of itself past the bottom edge after one swipe — not hittable
        // — with the next swipe already large enough to carry it past the top before this
        // loop ever reads it settled. Measured on the lane simulator: "Fine Print"'s row sat
        // at y 891–1037 of a 956 pt-tall screen (never hittable, centre past the bottom
        // edge), and the row was gone from the tree by the next swipe — not a wider defect
        // in the shelf, the rail or the banner, which the element dump showed not
        // overlapping it. The shelf's own alphabetical index does not have this problem,
        // because a chosen letter scrolls its first row to the very top — ask it for this
        // title's own initial before giving up.
        if found == nil, let initial = title.first.map({ String($0).uppercased() }) {
            // The index is one scrubber (24.6): tap it where the initial would sit in A to Z.
            let rail = app.descendants(matching: .any).matching(identifier: "library.rail").firstMatch
            if rail.isHittable, let letter = initial.unicodeScalars.first, ("A"..."Z").contains(letter) {
                let place = (Double(letter.value - 65) + 0.5) / 27
                rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: place)).tap()
                for _ in 0..<4 where found == nil {
                    found = wanted.allElementsBoundByIndex.first(where: \.isHittable)
                    if found == nil { app.swipeUp() }
                }
            }
        }
        try XCTSkipUnless(found != nil, "This device's shelf never showed a cover for “\(title)”.")
        found?.tap()

        guard app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 20)
        else { throw XCTSkip("“\(title)”'s page offered no hittable way to open it.") }
        // At the largest accessibility text sizes the action sits lower than one screen,
        // behind the title and the cover — scroll for it the way `scrollTo` does elsewhere.
        var action = app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable)
        for _ in 0..<4 where action == nil {
            app.swipeUp()
            action = app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable)
        }
        guard let action else {
            throw XCTSkip("“\(title)”'s page offered no hittable way to open it.")
        }
        action.tap()

        XCTAssertTrue(
            app.buttons["Close"].waitForExistence(timeout: 15),
            "Opening “\(title)” reached no reader — there is no way out on screen."
        )
        hold(2)
    }

    /// Brings the two controls back after the countdown has taken them.
    private func revealChrome(in app: XCUIApplication) throws {
        hold(6)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(
            app.buttons["Menu"].waitForExistence(timeout: 5),
            "A centre tap revealed no chrome."
        )
    }

    /// Opens the reader's menu, proving the sheet is up rather than the page behind it.
    private func openMenu(in app: XCUIApplication) throws {
        try XCTUnwrap(revealed("Menu", in: app), "The reader revealed no menu to open.").tap()
        XCTAssertTrue(
            hittableRow("Contents", in: app) != nil,
            "The menu did not open: it offers no Contents row. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
    }

    /// Taps Contents, and proves the carousel is up and runs the way the comic reads.
    ///
    /// The direction is asserted, not assumed. A walk that picks right-to-left stores it for
    /// the shelf, and frames that were named light and dark then showed right-to-left.
    @discardableResult
    private func openPageBrowser(in app: XCUIApplication, rightToLeft: Bool = false) throws -> XCUIElement {
        try XCTUnwrap(hittableRow("Contents", in: app), "The menu offers no Contents row.").tap()
        let page = { (number: Int) in
            app.buttons.matching(
                NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "Page \(number)", "Page \(number),")
            ).firstMatch
        }
        let second = page(2)
        XCTAssertTrue(second.waitForExistence(timeout: 8), "Contents opened no page browser.")
        XCTAssertEqual(
            second.frame.midX < page(1).frame.midX, rightToLeft,
            "The carousel does not put page 2 on the \(rightToLeft ? "left" : "right") of page 1."
        )
        return second
    }
}
