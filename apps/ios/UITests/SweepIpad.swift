import XCTest

/// The iPad, in landscape.
///
/// `docs/designs/screenshots/after-2026-08-30/` holds sixteen iPad frames and every one of
/// them is portrait, which leaves the orientation the sidebar was designed for unphotographed.
/// `.tabViewStyle(.sidebarAdaptable)` makes the same four destinations a sidebar in a regular
/// window, and `LibrarySidebar` adds two sections below them that a phone never draws at all —
/// so a landscape iPad is not a wider iPhone, it is a shell with rows nothing else has.
///
/// Run with `--device` pointed at an iPad. It skips on a compact window rather than filing a
/// phone's frames under an iPad's name.
///
/// The four moves this needs — `landscape()`, `portrait()`, `go(to:in:)` and
/// `showSidebar(in:)` — are in `IpadWalk.swift`, shared with ``SweepIpadPaneTests``.
@MainActor
final class SweepIpadTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // Put the device back. An orientation is device state, and the next suite's phone
        // frames would be landscape without this.
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// Home, in landscape, with the sidebar showing.
    func testCaptureIpadHome() throws {
        let app = try landscape()
        try go(to: "Home", in: app)
        hold(2.5)
        shutter(app, named: "ipad-home")
    }

    /// Home on an iPad **with something part-read**, which is the control the first frame
    /// needed and did not have.
    ///
    /// The September sweep read `ios-ipad-home.png` as "the widest window in the app drops
    /// the largest thing on the screen": the phone opens on *Continue reading* with a
    /// full-width cover and the iPad opened straight into *Recently added*. The device state
    /// was **not** the same. `HomeScreen` draws the hero on `model.continueReading` being
    /// non-empty and on nothing else — there is no size class anywhere in that decision —
    /// and reading positions live in a per-device SwiftData store that no launch argument
    /// reaches. The phone had read a book across four months of walks; this iPad, whose
    /// corpus was copied in on 2026-09-02, had never opened one.
    ///
    /// This walk reads one, and photographs Home afterwards. If the hero is in the frame,
    /// the finding was the empty device — which is exactly the mistake
    /// `one-library-three-destinations` task 0b.5 already records against Android's hero:
    /// "The review reported it missing because the device had nothing in progress."
    ///
    /// It is left in the suite rather than run once and deleted: it is the only iPad walk
    /// that photographs the hero at all, and the next person to look at an iPad's Home
    /// should find the frame beside the empty one rather than repeat the reading.
    func testCaptureIpadHomeInProgress() throws {
        let app = try landscape()
        try readAPage(in: app)
        try go(to: "Home", in: app)
        hold(3)
        shutter(app, named: "ipad-home-in-progress")
    }

    /// The library: the same shelf, given twice the width and asked how many columns it wants.
    ///
    /// `coverMinimumWidth(shelfWidth:textSize:)` steps to 158 pt past 900 pt of shelf, which
    /// is the tier a landscape iPad is in — "fewer, larger, more confident covers a big window
    /// is for" rather than the same lattice widened. This is the frame that says whether it is.
    func testCaptureIpadLibrary() throws {
        let app = try landscape()
        try go(to: "Library", in: app)
        hold(2.5)
        shutter(app, named: "ipad-library")
    }

    /// The library at the largest accessibility text size, where the tier steps again.
    func testCaptureIpadLibraryAtLargestText() throws {
        let app = try landscape(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try go(to: "Library", in: app)
        hold(2.5)
        shutter(app, named: "ipad-library-ax5")
    }

    /// The library as a list, where a row has an iPad's whole width to fill.
    func testCaptureIpadList() throws {
        let app = try landscape(layout: "list")
        try go(to: "Library", in: app)
        hold(2.5)
        shutter(app, named: "ipad-library-list")
    }

    /// Downloads, in landscape.
    func testCaptureIpadDownloads() throws {
        let app = try landscape()
        try go(to: "Downloads", in: app)
        hold(2.5)
        shutter(app, named: "ipad-downloads")
    }

    /// Search at rest, in landscape, where three suggestion shelves have room to be shelves.
    func testCaptureIpadSearch() throws {
        let app = try landscape()
        try go(to: "Search", in: app)
        hold(2.5)
        shutter(app, named: "ipad-search")
    }

    /// The sidebar itself: four destinations, then the library's sections and the reader's
    /// shelves under their own headers.
    ///
    /// The rows below the four are the whole reason this suite exists — they are hidden from
    /// the tab bar and exist only in a regular window, so no phone capture can show them.
    func testCaptureIpadSidebar() throws {
        let app = try landscape()
        try showSidebar(in: app)
        hold(1.5)
        shutter(app, named: "ipad-sidebar")
    }

    /// A publication page in the detail column, which on an iPad is the page beside the shelf
    /// rather than the page instead of it.
    ///
    /// **This docstring was a claim about a layout the app did not have.** It said "the
    /// detail column" while the shelf was a `NavigationStack` and the page was pushed over it,
    /// so the walk photographed a page *instead of* the shelf and filed it under a name saying
    /// beside. Nothing failed, because a screenshot suite asserts what it can reach and this
    /// one could reach a page either way. The claim is now checked rather than written down —
    /// see ``SweepIpadPaneTests`` for the case that fails when the shelf goes away.
    func testCaptureIpadDetail() throws {
        let app = try landscape()
        try go(to: "Library", in: app)
        hold(2.5)
        let covers = realCovers(in: app)
        try XCTSkipUnless(!covers.isEmpty, "This iPad's shelf drew no cover to open.")
        covers[0].tap()
        XCTAssertTrue(
            app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 10),
            "The cover reached no publication page."
        )
        hold(2)
        shutter(app, named: "ipad-detail")
    }

    /// A reader filling an iPad in landscape, which is the two-page question: does the spread
    /// pair up, and where does the chrome sit when there is this much of it?
    func testCaptureIpadReader() throws {
        let app = try landscape()
        try go(to: "Library", in: app)
        hold(2.5)
        let covers = coversOnScreen(in: app, ofFormat: "CBZ")
        try XCTSkipUnless(!covers.isEmpty, "This iPad's shelf drew no CBZ cover.")
        covers[0].tap()
        guard app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 10),
              let action = app.buttons.matching(opensAPublication)
                  .allElementsBoundByIndex.first(where: \.isHittable)
        else { throw XCTSkip("The publication page offered no hittable way in.") }
        action.tap()
        XCTAssertTrue(
            app.buttons["Close"].waitForExistence(timeout: 15),
            "Opening the comic reached no reader."
        )
        hold(3)
        shutter(app, named: "ipad-comic-reader")
    }

    // MARK: - The walk

    /// Opens a comic, turns a page, and comes back out — so that this device has something
    /// `LibraryIndex.continueReading` will call in progress.
    ///
    /// **One page of a long comic, and it has to be both.** The projection asks for
    /// `.inProgress`, and `home-screen` removes a publication from Keep reading the moment it
    /// is finished — so reaching the last page produces the same empty Home for the opposite
    /// reason. Two earlier runs of this did exactly that and photographed a Home carrying a
    /// *Finished* shelf and no hero, which would have read as the finding confirmed.
    ///
    /// `Tidal Reach` is eight pages (`scripts/corpus.mjs`), which is the margin that makes one
    /// swipe safe; `Foreign Codec` is three and the first run finished it. It is reached from
    /// Home's *Recently added* shelf rather than from the library grid, because the grid is
    /// sorted by title and the long comics are past the first screenful of it.
    private func readAPage(in app: XCUIApplication) throws {
        try go(to: "Home", in: app)
        hold(2.5)
        // Not `coversOnScreen(in:)`. That asks every button on the screen whether it is
        // hittable, and a lazy horizontal shelf holds cells whose frames the platform
        // refuses to answer for — "Failed to determine hittability of Paper Lanterns
        // Button: Activation point invalid", which is a thrown error rather than a `false`
        // and fails the walk before it reaches the comic. Judged on the frame instead.
        let named = NSPredicate(format: "label BEGINSWITH 'Tidal Reach'")
        let window = app.frame
        guard let cover = app.buttons.matching(named).allElementsBoundByIndex.first(where: {
            let box = $0.frame
            return box.width > 40 && window.contains(box)
        }) else {
            throw XCTSkip(
                "Home's shelves offered no Tidal Reach issue to part-read. Buttons: "
                    + "\(app.buttons.allElementsBoundByIndex.prefix(16).map(\.label))"
            )
        }
        cover.tap()
        guard app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 10),
              let action = app.buttons.matching(opensAPublication)
                  .allElementsBoundByIndex.first(where: \.isHittable)
        else { throw XCTSkip("The publication page offered no hittable way in.") }
        action.tap()
        try XCTSkipUnless(
            app.buttons["Close"].waitForExistence(timeout: 15),
            "Opening the comic reached no reader, so nothing can be part-read."
        )
        hold(2)
        app.swipeLeft()
        hold(1.5)
        // Out through the reader's own control. A back swipe on an iPad in landscape lands
        // on the page-turn gesture as readily as on the navigation one.
        if app.buttons["Close"].isHittable {
            app.buttons["Close"].tap()
        } else {
            app.tap()
            hold(1)
            app.buttons["Close"].tap()
        }
        hold(2)
    }
}
