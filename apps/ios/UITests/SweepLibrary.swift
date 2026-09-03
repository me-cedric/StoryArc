import XCTest

/// The library destination, every way it can be drawn and every menu it opens.
///
/// One of nine sweep suites taken for `docs/designs/screenshots/ios-sweep-2026-09-02/`. The
/// existing `ScreenshotTests` photographs the shelf at rest, at the largest text size and
/// scrolled to its end; what it has never photographed is the shelf *doing* anything — the
/// two named menus the toolbar was cut down to, either of them open, a filter actually set,
/// the compact list, or a selection with something in it.
///
/// **Every walk here proves the state before the shutter.** A menu that failed to open leaves
/// the shelf on screen and a screenshot of the shelf is a perfectly plausible picture of a
/// menu that has no visible frame — `AuditWalk.swift` makes the argument at length, and the
/// menus are the sharpest case of it in the app.
@MainActor
final class SweepLibraryTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - How the shelf is drawn

    /// The cover grid, which is the shelf's default layout.
    ///
    /// `ScreenshotTests.testCaptureLibrary` takes the same picture and this one is still
    /// worth taking: that walk takes the device's stored appearance, and this device's was
    /// `oledDark` — so its light captures were true black. `sweepLaunch` pins the appearance
    /// to `system` and hands the decision to the harness's `--appearance`.
    func testCaptureCoverGrid() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        hold(1)
        shutter(app, named: "library-grid")
    }

    /// The compact list, chosen through the View menu the layout toggle folded into.
    ///
    /// `library-browsing` offers grid and list; nothing in this repository has photographed
    /// the list on iOS. Android's equivalent is in `sort-chip-2026-09-01`.
    func testCaptureCompactList() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        try openViewMenu(in: app)
        try XCTUnwrap(hittable("List", in: app), "The View menu offers no List layout.").tap()
        try assertIsAList(app)
        hold(1.5)
        shutter(app, named: "library-list")
    }

    /// The list at the largest accessibility text size, where a row has the most to lose.
    func testCaptureCompactListAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try showTheShelf(in: app)
        try openViewMenu(in: app)
        try XCTUnwrap(hittable("List", in: app), "The View menu offers no List layout.").tap()
        try assertIsAList(app)
        // Longer than its default-size twin, and measured rather than padded: the shutter
        // itself timed out here once — "Failed to get screenshot: Timed out while requesting
        // screenshot" — while the list was still laying out rows a cell and a half tall.
        hold(3)
        shutter(app, named: "library-list-ax5")
    }

    // MARK: - The two named menus, open

    /// The View menu: availability, layout, sort and direction, in one place.
    ///
    /// Four pickers behind one word, which is what the toolbar's six unlabelled glyphs became.
    /// Whether one menu is the right home for four unrelated choices is exactly the question a
    /// design reviewer can answer from this picture and cannot answer from the source.
    func testCaptureViewMenu() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        try openViewMenu(in: app)
        hold(0.75)
        shutter(app, named: "library-view-menu")
    }

    /// The same menu at the largest accessibility text size.
    ///
    /// A system menu grows with the reader's type and the screen does not, so this is where a
    /// four-picker menu either scrolls or runs off the bottom.
    func testCaptureViewMenuAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try showTheShelf(in: app)
        try openViewMenu(in: app)
        hold(0.75)
        shutter(app, named: "library-view-menu-ax5")
    }

    /// The Filter menu with nothing set: seven groups and no way to clear.
    ///
    /// *Clear filters* is absent rather than disabled when nothing is filtered, which is a
    /// claim only a picture of the unfiltered menu can settle.
    func testCaptureFilterMenu() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        try openFilterMenu(in: app)
        hold(0.75)
        shutter(app, named: "library-filter-menu")
    }

    /// The Filter menu at the largest accessibility text size.
    func testCaptureFilterMenuAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try showTheShelf(in: app)
        try openFilterMenu(in: app)
        hold(0.75)
        shutter(app, named: "library-filter-menu-ax5")
    }

    /// A filter actually set, and the menu re-opened over it.
    ///
    /// Two frames, because the requirement has two halves. `library-browsing` asks that the
    /// active count be "visible on the control" and that one action clear them all — so the
    /// shelf with the control in its filtered state is one picture, and the menu carrying
    /// *Clear filters* is the other. The count itself is spoken rather than drawn: a menu
    /// label cannot carry a badge, so the control states it as an accessibility value and the
    /// only visible difference is a filled glyph. That is worth a reviewer's attention and it
    /// is why both frames are here.
    func testCaptureFilterActive() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        try setUnreadFilter(in: app)
        // The requirement's own wording — "the active count is visible on the control" — and
        // the only assertion here that cannot pass on an unfiltered shelf. A picture of a
        // filtered library looks very like a picture of an unfiltered one when almost
        // everything in the corpus is unread, which is exactly this device.
        let control = app.buttons.matching(NSPredicate(format: "label == %@", "Filter")).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5), "The toolbar lost its Filter control.")
        XCTAssertEqual(
            control.value as? String, "1 filter active",
            "The Filter control does not state that one filter is set, so the filter did not take."
        )
        hold(1)
        shutter(app, named: "library-filtered")

        try openFilterMenu(in: app)
        // Seven groups, a divider and the clear — more rows than a menu shows on a phone at
        // some text sizes, so it is scrolled to rather than asserted into existence.
        if hittable("Clear filters", in: app, timeout: 2) == nil { app.swipeUp() }
        hold(0.75)
        shutter(app, named: "library-filter-menu-active")
    }

    /// Every filter set to something nothing matches: a library with books and none on screen.
    ///
    /// `NarrowedToNothing` writes four different sentences depending on what is hiding the
    /// shelf, and no picture of any of them exists. This is the filtered one, reached by
    /// narrowing on read state and download state at once — the AND that
    /// `library-browsing` specifies, doing what a reader would not expect it to.
    func testCaptureNarrowedToNothing() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        try setUnreadFilter(in: app)
        try openFilterMenu(in: app)
        try XCTUnwrap(
            hittable("Downloaded or not", in: app),
            "The Filter menu offers no download group."
        ).tap()
        // *Not downloaded*, not *Downloaded*, and the difference is the whole test. Every
        // publication on this device is a local file, and `DownloadFilter.keeps(isDownloaded:)`
        // counts a local file as downloaded — so *Downloaded* excludes nothing and the shelf
        // stayed full under a filename saying it was empty. The complement excludes everything.
        try XCTUnwrap(hittable("Not downloaded", in: app), "No Not-downloaded option.").tap()

        // Any of the four, not one of them. `NarrowedToNothing` chooses its sentence from the
        // *reason* — a search term, the device axis, the filters, or one library — and which
        // reason wins for two filters at once is the screen's own decision rather than this
        // walk's. Asserting the filtered wording named a defect that was a correct answer.
        let sentences = [
            "Nothing matches the filters you set.",
            "Nothing in your library is on this device yet.",
        ]
        let empty = app.staticTexts.matching(
            NSPredicate(format: "label IN %@", sentences)
        ).firstMatch
        XCTAssertTrue(
            empty.waitForExistence(timeout: 8),
            "Two filters that cannot both hold left publications on the shelf. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        shutter(app, named: "library-narrowed-to-nothing")
    }

    /// The shelf narrowed to what opens with no network, which is a mode rather than a filter.
    ///
    /// It is the one narrowing the toolbar states in its own glyph — `ViewMenu` swaps the
    /// platform's view-options icon for the availability symbol while it is on — so the
    /// picture is as much about the control as about the shelf.
    func testCaptureNarrowedToDevice() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        try openViewMenu(in: app)
        try XCTUnwrap(
            hittable("On this device", in: app),
            "The View menu offers no availability picker."
        ).tap()
        hold(1.5)
        shutter(app, named: "library-on-this-device")
    }

    // MARK: - Adding somewhere to read from

    /// The Add-books menu: the five ways in, and the only way in on iOS.
    func testCaptureAddBooksMenu() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        try XCTUnwrap(hittable("Add books", in: app), "The toolbar offers no Add books.").tap()
        XCTAssertTrue(
            app.buttons["Add a folder"].waitForExistence(timeout: 5),
            "Add books opened no menu. Buttons: \(app.buttons.allElementsBoundByIndex.map(\.label))"
        )
        hold(0.75)
        shutter(app, named: "library-add-books")
    }

    /// The same menu at the largest accessibility text size, where five rows of two lines each
    /// is the most this control ever has to fit.
    func testCaptureAddBooksMenuAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try showTheShelf(in: app)
        try XCTUnwrap(hittable("Add books", in: app), "The toolbar offers no Add books.").tap()
        XCTAssertTrue(
            app.buttons["Add a folder"].waitForExistence(timeout: 5),
            "Add books opened no menu at the largest text size."
        )
        hold(0.75)
        shutter(app, named: "library-add-books-ax5")
    }

    // MARK: - Selecting

    // **Not here, and deliberately.** The selection chrome was rebuilt while this sweep was
    // being taken — the tab bar hides, the actions float as a glass capsule where it was, the
    // count moved into the navigation title and *Done* into the toolbar — and
    // `LibrarySelectionCapture.swift` landed with it, carrying two walks: the capsule live
    // with two covers picked, and the same at the largest accessibility text size.
    // `ScreenshotTests.testCaptureLibrarySelectingAtTheEnd` carries the third, the mode
    // scrolled to the end of the shelf where the inset is decided.
    //
    // Three walks for one surface written twice is how two of them come to disagree, which is
    // the argument `AuditWalk.opensAPublication` makes about a predicate that existed in two
    // copies and matched nothing in one of them. The sweep's README says which commands
    // produce those frames into its own folder.
    //
    // The `Add to…` menu a selection opens is still uncaptured, and it is the same menu a
    // long press on a single cover gives — `AddToShelfMenu` — so it belongs with whichever
    // walk owns the new capsule rather than with a fourth one here.

    // MARK: - The walk

    /// That the shelf is drawn as a list rather than a grid.
    ///
    /// A SwiftUI `List` is a collection view, not a scroll view — and waiting on
    /// `app.scrollViews` after choosing *List* therefore timed out on a screen that had done
    /// exactly what it was asked. The grid is the scroll view; the list is the collection.
    private func assertIsAList(_ app: XCUIApplication) throws {
        XCTAssertTrue(
            app.collectionViews.firstMatch.waitForExistence(timeout: 10),
            "Choosing List left no list on screen."
        )
    }

    /// Narrows the shelf to unread through the Filter menu, the way a reader would.
    ///
    /// Driven rather than injected. A `libraryQuery` written straight into the argument domain
    /// would narrow the shelf and leave the *control* untouched — and half of what these
    /// captures are for is what the control says while a filter is on.
    private func setUnreadFilter(in app: XCUIApplication) throws {
        try openFilterMenu(in: app)
        try XCTUnwrap(
            hittable("Read or unread", in: app),
            "The Filter menu offers no read-state group."
        ).tap()
        try XCTUnwrap(hittable("Unread", in: app), "The read-state group offers no Unread.").tap()
    }
}
