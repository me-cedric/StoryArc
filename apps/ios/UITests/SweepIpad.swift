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

    /// One destination, whatever a sidebar makes of it.
    ///
    /// **`destination(_:in:)` cannot see these.** It asks for a `tabBars` button, a button and
    /// a static text — which is the right set for a phone's tab bar and the wrong one for a
    /// regular window, where `.sidebarAdaptable` draws the same four entries as rows of a
    /// `List` and the platform calls them cells. Six iPad walks failed with "no Home" on a
    /// window whose sidebar had *Home* at the top of it.
    ///
    /// `control(_:in:)` already tries cells, and is what `AuditWalk` reaches for when a row is
    /// a `NavigationLink` rather than a button. The sidebar is asked to open first, because a
    /// window that starts with it collapsed has no rows to find.
    private func go(to name: String, in app: XCUIApplication) throws {
        var entry = sidebarEntry(name, in: app)
        if entry == nil {
            try? showSidebar(in: app)
            hold(1)
            entry = sidebarEntry(name, in: app)
        }
        try XCTUnwrap(
            entry,
            "This window offers no way to \(name). Cells: "
                + "\(app.cells.allElementsBoundByIndex.prefix(12).map(\.label)). Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(12).map(\.label))"
        ).tap()
        hold(1)
    }

    /// The sidebar row for a destination, out of everything that carries its name.
    ///
    /// **The name is not unique and the first match is not the row.** The sidebar lists the
    /// four destinations and then a *Library* section header above *Recently added* and
    /// *Series* — so `app.cells["Library"]` binds to whichever the platform ordered first,
    /// and `control(_:in:)`, which asks each element type for its subscript, gave up when
    /// that one was a header nobody can tap. Every match is considered, and the first one a
    /// finger could reach is the row.
    private func sidebarEntry(_ name: String, in app: XCUIApplication) -> XCUIElement? {
        let named = NSPredicate(format: "label == %@", name)
        for query in [app.cells.matching(named), app.buttons.matching(named)] {
            _ = query.firstMatch.waitForExistence(timeout: 3)
            if let hit = query.allElementsBoundByIndex.first(where: \.isHittable) { return hit }
        }
        return nil
    }

    /// Launches in landscape, and refuses to photograph a compact window under an iPad's name.
    ///
    /// The orientation is set before the launch so the first frame is already landscape —
    /// rotating afterwards photographs a layout mid-animation as readily as after it.
    private func landscape(contentSize: String? = nil, layout: String = "grid") throws -> XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = sweepLaunch(contentSize: contentSize, layout: layout)
        hold(2)
        try XCTSkipUnless(
            app.frame.width > app.frame.height,
            "This device is \(Int(app.frame.width))×\(Int(app.frame.height)) — not landscape, "
                + "so these frames would be filed under a name they do not match."
        )
        try XCTSkipUnless(
            app.frame.width >= 700,
            "This window is \(Int(app.frame.width)) points wide, which is a compact shell "
                + "rather than an iPad's. Run this suite with --device pointed at an iPad."
        )
        return app
    }

    /// Reveals the sidebar, whichever control this window draws for it.
    ///
    /// A regular window may open with the sidebar already out, or with the tab bar and a
    /// toggle. Both are the platform's decision rather than the app's, so this takes either
    /// and says which it found.
    private func showSidebar(in app: XCUIApplication) throws {
        if app.buttons["All shelves"].exists { return }
        let toggle = app.buttons.matching(
            NSPredicate(format: "identifier CONTAINS[c] %@ OR label CONTAINS[c] %@", "sidebar", "sidebar")
        ).firstMatch
        if toggle.waitForExistence(timeout: 5), toggle.isHittable { toggle.tap() }
        hold(1.5)
        try XCTSkipUnless(
            app.buttons["All shelves"].waitForExistence(timeout: 5)
                || app.staticTexts["Library"].exists,
            "This window revealed no sidebar. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(25).map(\.label))"
        )
    }
}
