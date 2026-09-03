import XCTest

/// The four sheets a reader adds a library through, and the browser one of them leads to.
///
/// None of them has a picture. They are the app's only real forms — an address, a user name, a
/// secret and a hint apiece — and `sources` is specific about what each has to say: where the
/// secret is kept, what the address may look like, and what a refusal means. A form is exactly
/// the kind of surface a source-level test cannot judge.
///
/// **The pickers are screen shots rather than app shots.** *Add a folder* and *Open a file*
/// both put up the system's own document browser, which runs in another process — `app
/// .screenshot()` photographs StoryArc's window and would return the shelf behind it.
@MainActor
final class SweepSourcesTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Adding an OPDS catalogue: the address, the hint naming five server products, and the
    /// action.
    func testCaptureAddCatalogueSheet() throws {
        let app = sweepLaunch()
        try openAddSheet("Add an online library", landmark: "Address", in: app)
        shutter(app, named: "add-catalogue-sheet")
    }

    /// The same at the largest accessibility text size, where the hint is three lines.
    func testCaptureAddCatalogueSheetAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openAddSheet("Add an online library", landmark: "Address", in: app)
        shutter(app, named: "add-catalogue-sheet-ax5")
    }

    /// Adding a Kavita server: the address, the API key, and where the key is kept.
    func testCaptureAddKavitaSheet() throws {
        let app = sweepLaunch()
        try openAddSheet("Kavita library", landmark: "API key", in: app)
        shutter(app, named: "add-kavita-sheet")
    }

    /// Adding a network share: host, share, user name and password, plus what is on this
    /// network — the only form in the app with a discovery list under it.
    func testCaptureAddShareSheet() throws {
        let app = sweepLaunch()
        try openAddSheet("Add a shared folder", landmark: "Host", in: app)
        hold(2)
        shutter(app, named: "add-share-sheet")
    }

    /// The system's folder picker, which is the whole of *Add a folder* on iOS.
    func testCaptureFolderPicker() throws {
        let app = sweepLaunch()
        try openAddMenu(in: app)
        try XCTUnwrap(hittable("Add a folder", in: app), "no folder row").tap()
        try shutterSystemSheet(named: "add-folder-picker", in: app)
    }

    /// The same picker in its file-choosing mode, which is *Open a file*.
    func testCaptureFilePicker() throws {
        let app = sweepLaunch()
        try openAddMenu(in: app)
        try XCTUnwrap(hittable("Open a file", in: app), "no import row").tap()
        try shutterSystemSheet(named: "add-file-picker", in: app)
    }

    /// The catalogue browser: a live OPDS server's own shelves, inside StoryArc.
    ///
    /// It skips unless one is answering. `scripts/opds-server.mjs` is the one this device is
    /// configured against — `pnpm opds` — and without it the browser is a screen full of the
    /// error states, which are worth photographing separately and are not this.
    func testCaptureCatalogueBrowser() throws {
        let app = sweepLaunch()
        try openSettings(in: app)
        try XCTUnwrap(control("Your libraries", in: app), "no libraries row").tap()
        guard let catalogue = control("StoryArc Test Catalogue", in: app) else {
            throw XCTSkip("This device lists no test catalogue to browse.")
        }
        catalogue.tap()
        hold(3)
        shutter(app, named: "source-catalogue-detail")
    }

    /// A source that cannot be reached, stated on its own page.
    ///
    /// Two of this device's five sources point at hosts that are not running, so *Not
    /// answering* and *No answer since …* are the states this page is actually in — and
    /// `AGENTS.md`'s second non-negotiable is that an unreachable source is grey, never red.
    /// This is the frame that says whether it is.
    func testCaptureUnreachableSourceDetail() throws {
        let app = sweepLaunch()
        try openSettings(in: app)
        try XCTUnwrap(control("Your libraries", in: app), "no libraries row").tap()
        guard let source = control("Attic NAS", in: app) else {
            throw XCTSkip("This device lists no unreachable catalogue.")
        }
        source.tap()
        XCTAssertTrue(
            app.staticTexts["Status"].waitForExistence(timeout: 5),
            "The source did not open a page stating its status."
        )
        hold(3)
        shutter(app, named: "source-unreachable-detail")
    }

    /// The library-wide notice when nothing a reader added can be reached.
    ///
    /// `library-browsing`: "None of the places you added can be reached right now. Anything
    /// already on this device is still here to read." It is the sentence the offline promise
    /// rests on and it has no picture.
    func testCaptureAwayNotice() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        hold(4)
        guard app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "None of the places you added")
        ).firstMatch.exists else {
            throw XCTSkip(
                "This device's shelf shows no unreachable-sources notice: it has local files, "
                    + "so the library is not away."
            )
        }
        shutter(app, named: "library-sources-away")
    }

    // MARK: - The walk

    /// Opens the Add-books menu on the shelf.
    private func openAddMenu(in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        try XCTUnwrap(hittable("Add books", in: app), "The toolbar offers no Add books.").tap()
        XCTAssertTrue(
            app.buttons["Add a folder"].waitForExistence(timeout: 5),
            "Add books opened no menu."
        )
    }

    /// Opens one add-source sheet and proves it is the right one.
    ///
    /// The landmark is a field label that only that sheet has: all three forms carry an
    /// address, and only Kavita carries an API key, only the share a Host.
    private func openAddSheet(_ row: String, landmark: String, in app: XCUIApplication) throws {
        try openAddMenu(in: app)
        try XCTUnwrap(hittable(row, in: app), "The Add-books menu has no \(row) row.").tap()
        XCTAssertTrue(
            app.staticTexts[landmark].waitForExistence(timeout: 8)
                || app.textFields[landmark].waitForExistence(timeout: 2),
            "\(row) opened no sheet carrying “\(landmark)”. Texts: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        hold(1)
    }

    /// Photographs the whole screen, for a sheet drawn by another process.
    private func shutterSystemSheet(named name: String, in app: XCUIApplication) throws {
        hold(3)
        // The picker is `com.apple.DocumentManagerUICore`'s, so StoryArc's own hierarchy is
        // the wrong thing to ask. That it is up at all is asserted through the springboard's
        // view of the screen: the shelf's toolbar is behind it and no longer hittable.
        XCTAssertFalse(
            app.buttons["Add books"].isHittable,
            "No system sheet came up over the shelf — the toolbar is still reachable."
        )
        shutter(shot: XCUIScreen.main.screenshot(), named: name)
    }
}
