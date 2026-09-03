import XCTest

/// The reflowable reader and the six surfaces behind its menu.
///
/// `ScreenshotTests` photographs the page on arrival, after the countdown, after a centre tap,
/// and the theme sheet's preset grid. What it has never photographed is the menu those
/// presets are reached through, the axes screen behind *Customise* — nine typographic
/// controls, which is the largest single settings surface in the app — the contents, the
/// search, the bookmarks or the notes.
///
/// The walk is `openTheEpubReader(in:)`, in `EpubWalk.swift`. It searches rather than assuming:
/// a cover says `EPUB` whether the book is reflowable or pre-paginated, and the app opens
/// those in two different readers.
@MainActor
final class SweepEpubReaderTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The page with nothing on it: the reader as a reader spends their time in it.
    func testCaptureEpubPage() throws {
        let app = sweepLaunch()
        try openTheEpubReader(in: app)
        hold(6)
        shutter(app, named: "epub-reader-page")
    }

    /// The menu: five doors and a read-aloud row, at the medium detent with the page behind.
    func testCaptureEpubMenu() throws {
        let app = sweepLaunch()
        try openTheEpubReader(in: app)
        try openMenu(in: app)
        hold(1)
        shutter(app, named: "epub-reader-menu")
    }

    /// The menu at the largest accessibility text size.
    func testCaptureEpubMenuAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openTheEpubReader(in: app)
        try openMenu(in: app)
        hold(1)
        shutter(app, named: "epub-reader-menu-ax5")
    }

    /// The theme sheet's first level: six presets, each drawn in its own colours and its own
    /// typeface, plus the text-size stepper and the brightness slider.
    ///
    /// `ScreenshotTests.testCaptureThemeSheet` takes this too. It is here as well because it
    /// is the screen `epub-theme-axes` is reached *from*, and a reviewer looking at the axes
    /// needs the level above it in the same folder and the same appearance.
    func testCaptureEpubThemePresets() throws {
        let app = sweepLaunch()
        try openThemeSheet(in: app)
        hold(1.5)
        shutter(app, named: "epub-theme-presets")
    }

    /// The axes screen: typeface, text size, line spacing, paragraph spacing, word and
    /// character spacing, margins, alignment, hyphenation and bold text.
    ///
    /// **Nine controls on one screen, and no picture of it exists.** `reading-themes` asks
    /// for each axis to state its own value in words rather than as a slider position, and
    /// whether nine of them read as a settings screen or as a wall is the question here.
    func testCaptureEpubThemeAxes() throws {
        let app = sweepLaunch()
        try openThemeSheet(in: app)
        try XCTUnwrap(hittableRow("Customise", in: app), "The theme sheet offers no Customise.").tap()
        XCTAssertTrue(
            app.staticTexts["Line spacing"].waitForExistence(timeout: 5)
                || app.staticTexts["Typeface"].waitForExistence(timeout: 3),
            "Customise opened no axes screen. Texts: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(25).map(\.label))"
        )
        hold(1)
        shutter(app, named: "epub-theme-axes")
    }

    /// The axes screen at the largest accessibility text size, where every row is a name and
    /// a value that have to share a line.
    func testCaptureEpubThemeAxesAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openThemeSheet(in: app)
        try XCTUnwrap(hittableRow("Customise", in: app), "The theme sheet offers no Customise.").tap()
        hold(1.5)
        shutter(app, named: "epub-theme-axes-ax5")
    }

    /// The axes screen scrolled to the page-colour control, where a reader's own colour is
    /// accepted or refused on contrast.
    ///
    /// `reading-themes` refuses a pairing below the floor and says the ratio. That refusal is
    /// the app's only visible contrast gate and it has no picture.
    func testCaptureEpubPageColour() throws {
        let app = sweepLaunch()
        try openThemeSheet(in: app)
        try XCTUnwrap(hittableRow("Customise", in: app), "The theme sheet offers no Customise.").tap()
        _ = scrollTo(app.staticTexts["Page colour"], in: app, swipes: 8)
        hold(0.75)
        shutter(app, named: "epub-theme-page-colour")
    }

    /// The table of contents.
    func testCaptureEpubContents() throws {
        let app = sweepLaunch()
        try openTheEpubReader(in: app)
        try openMenu(in: app)
        try XCTUnwrap(hittableRow("Contents", in: app), "The menu offers no Contents row.").tap()
        XCTAssertTrue(
            app.navigationBars["Contents"].waitForExistence(timeout: 5)
                || app.staticTexts["Contents"].waitForExistence(timeout: 3),
            "Contents opened nothing headed Contents."
        )
        hold(1)
        shutter(app, named: "epub-contents")
    }

    /// Search within the book, at rest.
    ///
    /// The field rather than a result set: typing into the simulator garbles ASCII, and the
    /// screen a reader lands on is the one with the empty field and its prompt on it.
    func testCaptureEpubSearch() throws {
        let app = sweepLaunch()
        try openTheEpubReader(in: app)
        try openMenu(in: app)
        try XCTUnwrap(hittableRow("Search", in: app), "The menu offers no Search row.").tap()
        hold(1.5)
        shutter(app, named: "epub-search")
    }

    /// Bookmarks, which on a book nobody has marked is an empty state with an instruction.
    func testCaptureEpubBookmarks() throws {
        let app = sweepLaunch()
        try openTheEpubReader(in: app)
        try openMenu(in: app)
        try XCTUnwrap(hittableRow("Bookmarks", in: app), "The menu offers no Bookmarks row.").tap()
        hold(1.5)
        shutter(app, named: "epub-bookmarks")
    }

    /// Notes and highlights, likewise empty and likewise instructive.
    func testCaptureEpubNotes() throws {
        let app = sweepLaunch()
        try openTheEpubReader(in: app)
        try openMenu(in: app)
        try XCTUnwrap(hittableRow("Notes", in: app), "The menu offers no Notes row.").tap()
        hold(1.5)
        shutter(app, named: "epub-notes")
    }

    /// A note being written, which needs a passage selected first.
    ///
    /// **Selection is in the web view, which is why this may skip.** A long press over
    /// reflowable text is WebKit's own gesture and the menu it puts up is WebKit's, extended
    /// by `SelectionMenu`. A press that lands between words selects nothing and there is no
    /// menu — so the walk states what it saw rather than photographing the page.
    func testCaptureEpubNoteDialog() throws {
        let app = sweepLaunch()
        try openTheEpubReader(in: app)
        hold(3)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.4)).press(forDuration: 1.2)
        hold(1.5)
        guard let note = hittable("Note", in: app, timeout: 3) else {
            throw XCTSkip(
                "A long press over the page put up no menu offering Note. Buttons: "
                    + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
            )
        }
        note.tap()
        hold(1)
        shutter(app, named: "epub-note-dialog")
    }

    /// The reader with a book being read aloud, so the docked transport is over the page.
    func testCaptureEpubReadAloud() throws {
        let app = sweepLaunch()
        try openTheEpubReader(in: app)
        try openMenu(in: app)
        guard let start = hittableRow("Read aloud", in: app, timeout: 3) else {
            throw XCTSkip(
                "The menu offers no read-aloud row on this publication. Buttons: "
                    + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
            )
        }
        start.tap()
        hold(4)
        shutter(app, named: "epub-read-aloud")
    }

    // MARK: - The walk

    /// Reveals the chrome and opens the menu, proving the sheet is up.
    private func openMenu(in app: XCUIApplication) throws {
        try XCTUnwrap(revealed("Menu", in: app), "The reader revealed no menu to open.").tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reading themes")).firstMatch.waitForExistence(timeout: 5),
            "The menu did not open: it offers no reading-themes row. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
    }

    /// The theme sheet, over a page in the reflowable reader.
    private func openThemeSheet(in app: XCUIApplication) throws {
        try openTheEpubReader(in: app)
        try openMenu(in: app)
        try XCTUnwrap(hittableRow("Reading themes", in: app), "no reading themes row").tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Original")
            ).firstMatch.waitForExistence(timeout: 8),
            "The theme sheet did not present its presets."
        )
    }
}
