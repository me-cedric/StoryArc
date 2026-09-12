import XCTest

/// The four sheets a reader adds a library through, and the browser one of them leads to.
///
/// None of them has a picture. They are the app's only real forms — an address, a user name, a
/// secret and a hint apiece — and `sources` is specific about what each has to say: where the
/// secret is kept, what the address may look like, and what a refusal means. A form is exactly
/// the kind of surface a source-level test cannot judge.
///
/// **The pickers are screen shots rather than app shots.** *Files and folders* and *Open a file*
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
        try openAddSheet("Online library", landmark: "Address", in: app)
        shutter(app, named: "add-catalogue-sheet")
    }

    /// The same at the largest accessibility text size, where the hint is three lines.
    func testCaptureAddCatalogueSheetAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openAddSheet("Online library", landmark: "Address", in: app)
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
        try openAddSheet("A computer on your network", landmark: "Host", in: app)
        hold(2)
        shutter(app, named: "add-share-sheet")
    }

    /// The system's folder picker, which is the whole of *Files and folders* on iOS.
    ///
    /// Named by `source.kind.localFolder.title`. It read *Add a folder* until the source
    /// kinds were given one vocabulary; four assertions here still asked for the old words,
    /// and each failed about a menu that had opened.
    func testCaptureFolderPicker() throws {
        let app = sweepLaunch()
        try openAddMenu(in: app)
        try XCTUnwrap(hittable("Files and folders", in: app), "no folder row").tap()
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
        // **Injected, and unreachable by construction.** This read the device's own registry
        // and skipped when it held no unreachable catalogue, which made the frame a matter of
        // whoever used the simulator last. ``MockCatalogues`` points one source at a port
        // nothing listens on, so this walk needs no server running at all — unlike its
        // reachable twin, it cannot be made to pass by luck.
        let app = sweepLaunch(sources: MockCatalogues.registry)
        try openSettings(in: app)
        try XCTUnwrap(control("Your libraries", in: app), "no libraries row").tap()
        guard let source = control(MockCatalogues.cellar, in: app) ?? control("Attic NAS", in: app) else {
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

    /// The same page at the largest accessibility text size.
    ///
    /// `source-lifecycle` §4.3 asks for this screen at both text sizes. It is the screen with
    /// the most to lose at `AccessibilityXXXL`: *No answer since Sep 5, 2026 at 15:02* already
    /// wraps to two lines at the default size, and it is the row that carries the claim — an
    /// unreachable source states what happened, in grey, without an alarm.
    func testCaptureUnreachableSourceDetailAtLargestText() throws {
        let app = sweepLaunch(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            sources: MockCatalogues.registry
        )
        try openSettings(in: app)
        try XCTUnwrap(control("Your libraries", in: app), "no libraries row").tap()
        // Scrolled to, unlike its default-size twin. *Cellar* is the third of three
        // catalogues, and at `AccessibilityXXXL` a list row is tall enough that the third one
        // starts below the fold — `control(_:in:)` asks for a hittable element, so it found
        // nothing and the walk failed about a row that was on the screen's other half.
        let cellar = app.staticTexts[MockCatalogues.cellar]
        XCTAssertTrue(scrollTo(cellar, in: app), "Your libraries never showed \(MockCatalogues.cellar).")
        cellar.tap()
        XCTAssertTrue(
            app.staticTexts["Status"].waitForExistence(timeout: 5),
            "The source did not open a page stating its status."
        )
        hold(3)
        shutter(app, named: "source-unreachable-detail-ax5")
    }

    /// The library-wide notice when nothing a reader added can be reached.
    ///
    /// `library-browsing`: "None of the places you added can be reached right now. Anything
    /// already on this device is still here to read." It is the sentence the offline promise
    /// rests on.
    ///
    /// **The registry is injected; the empty device is not, and cannot be.** One dead
    /// catalogue makes ``LibraryAway/everythingAway(in:)`` true — but the shelf reaches
    /// ``LibraryAway`` only after the *narrowed to nothing* branch, which is taken whenever
    /// the device holds a publication of its own. No launch argument empties `Documents`, so
    /// the seeded sweep simulator shows the filter sentence instead and this walk skips.
    ///
    /// To take the frame, clear the container first and put it back afterwards:
    ///
    /// ```
    /// xcrun simctl uninstall StoryArc-iPhone17Pro com.mecedric.storyarc
    /// pnpm capture:ios --only SweepSourcesTests/testCaptureAwayNotice --out <dir>
    /// node scripts/install-and-seed-simulator.mjs
    /// ```
    func testCaptureAwayNotice() throws {
        let app = sweepLaunch(sources: MockCatalogues.everythingAway)
        try showTheShelf(in: app)
        // The probe has to fail before the sentence can be drawn, and a refused connection on
        // a simulator is fast but not instant.
        hold(4)
        let notice = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "None of the places you added")
        ).firstMatch
        guard notice.waitForExistence(timeout: 10) else {
            throw XCTSkip(
                "This device holds books of its own, so the shelf answers with the narrowed-to-"
                    + "nothing sentence rather than the away notice. Uninstall the app first — "
                    + "the doc comment above carries the three commands."
            )
        }
        // The action, not just the sentence: `library-browsing` asks this state never to be a
        // dead end, and a frame of the sentence alone would not show that it is not one.
        XCTAssertTrue(app.buttons["Try again"].exists, "The away notice offers no way to retry.")
        shutter(app, named: "library-sources-away")
    }

    /// A source the library has never read, named at the foot of a shelf that still works.
    ///
    /// `library-browsing`'s *A source that has never been reached* asks for all three clauses
    /// in one frame: the library says the source has not been read yet, it names it, and "the
    /// rest of the library is complete and usable while it says so".
    ///
    /// **Injected, and unread by construction.** ``MockCatalogues/registry`` carries
    /// `lastSuccessfulSync: null` on all three catalogues and points *Cellar Catalogue* at a
    /// port nothing listens on, so this walk needs no server running. With the two mock
    /// catalogues up, Cellar is the only name in the sentence; with them down, all three are.
    /// Either way the assertion is Cellar, which cannot be reached in either world.
    ///
    /// Unlike ``testCaptureAwayNotice`` this wants a device that *does* hold books, because the
    /// complete shelf is half of what the frame has to show.
    func testCaptureNeverReachedNotice() throws {
        let app = sweepLaunch(sources: MockCatalogues.registry)
        try showTheShelf(in: app)
        // The probe has to fail before the sentence can be drawn, and a refused connection on
        // a simulator is fast but not instant.
        hold(4)
        let notice = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", MockCatalogues.cellar)
        ).firstMatch
        XCTAssertTrue(
            notice.waitForExistence(timeout: 15),
            "The shelf never named \(MockCatalogues.cellar), so a source that has never "
                + "answered is still silent."
        )
        // The action, not just the sentence: `library-browsing` asks the library to offer to
        // try again, and a frame of the sentence alone would not show that it does.
        XCTAssertTrue(app.buttons["Try again"].exists, "The notice offers no way to retry.")
        // The third clause. A notice drawn over an empty shelf would satisfy the first two and
        // break the one that matters most.
        XCTAssertFalse(
            realCovers(in: app).isEmpty,
            "This device's shelf shows no cover, so the frame cannot show that the rest of "
                + "the library stays usable. Seed it: node scripts/corpus.mjs --simulator <udid>"
        )
        shutter(app, named: "library-source-never-reached")
    }

    /// The same notice at the largest accessibility text size.
    ///
    /// The strip is a sentence with a button beside it on one line, so `AccessibilityXXXL` is
    /// where it has the most to lose. AGENTS.md §6 asks for both text sizes, and this is the
    /// frame that says whether the sentence and its action still both fit.
    func testCaptureNeverReachedNoticeAtLargestText() throws {
        let app = sweepLaunch(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            sources: MockCatalogues.registry
        )
        try showTheShelf(in: app)
        hold(4)
        let notice = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", MockCatalogues.cellar)
        ).firstMatch
        XCTAssertTrue(
            notice.waitForExistence(timeout: 15),
            "The shelf never named \(MockCatalogues.cellar) at the largest text size."
        )
        XCTAssertTrue(app.buttons["Try again"].exists, "The notice offers no way to retry.")
        shutter(app, named: "library-source-never-reached-ax5")
    }

    // MARK: - The walk

    /// Opens the Add-books menu on the shelf.
    private func openAddMenu(in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        try XCTUnwrap(hittable("Add books", in: app), "The toolbar offers no Add books.").tap()
        XCTAssertTrue(
            app.buttons["Files and folders"].waitForExistence(timeout: 5),
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
        // The picker is `com.apple.DocumentManagerUICore`'s, so StoryArc's own hierarchy is
        // the wrong thing to ask. That it is up at all is asserted through the shelf behind
        // it: the toolbar is covered and no longer hittable.
        //
        // Polled to ten seconds rather than waited out once, because the claim this makes if
        // it fails — *this control opens no picker* — is worth more than a three-second hold.
        var covered = false
        for _ in 0..<20 where !covered {
            hold(0.5)
            covered = !app.buttons["Add books"].isHittable
        }
        XCTAssertTrue(
            covered,
            "Nothing came up over the shelf in ten seconds — the toolbar is still reachable, "
                + "so this control presented no picker."
        )
        hold(1)
        shutter(shot: XCUIScreen.main.screenshot(), named: name)
    }
}
