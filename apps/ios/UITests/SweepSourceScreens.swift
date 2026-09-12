import XCTest

/// The screens a *source* has, which are where `source-lifecycle` is photographed.
///
/// Split out of `SweepSettings.swift` on 2026-09-12, when that file crossed the 400-line cap
/// `scripts/line-cap.mjs` holds. `AGENTS.md` asks for a split rather than a waiver, and the
/// seam was already there: settings screens above, one library's own screens below. They share
/// nothing but the way in.
///
/// **Every walk here decides what it is looking at.** They used to read the simulator's own
/// registry, which is whoever last used it — so one photographed a different screen each week
/// and another skipped outright on a device with no unreachable catalogue. ``MockCatalogues``
/// is injected through `sweepLaunch(sources:)` instead, and it holds two catalogues that
/// answer and one pointed at a port nothing listens on.
@MainActor
final class SweepSourceScreensTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Your libraries: the five sources this device carries, with their states.
    func testCaptureSettingsSources() throws {
        let app = sweepLaunch()
        try open("Your libraries", in: app)
        hold(1)
        shutter(app, named: "settings-sources")
    }

    /// A reachable source directly above an unreachable one, at one moment.
    ///
    /// `source-lifecycle` §4.3 asks for the control *in* the frame rather than beside it: an
    /// unreachable source is grey and never red, and a grey row proves nothing next to no
    /// other row. The earlier attempt at this could not get the pair — every source on that
    /// simulator was unreachable, so the two frames were two greys.
    ///
    /// ``MockCatalogues`` is why it works now: two catalogues that answer and one pointed at a
    /// port nothing listens on. Android's twin is `android-sources-pair-{light,dark}`.
    func testCaptureSourcesReachableAndNot() throws {
        guard MockCatalogues.areRunning() else {
            throw XCTSkip(
                "The mock catalogues are not running, so no source here is reachable. Start "
                    + "them: node scripts/opds-server.mjs <corpus> --port \(MockCatalogues.firstPort)"
            )
        }
        let app = sweepLaunch(sources: MockCatalogues.registry)
        try open("Your libraries", in: app)
        // Waited for rather than held: the state arrives from a probe, and a frame taken
        // before it lands shows two sources still connecting, which is neither of the states
        // this is about.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Not answering")
            ).firstMatch.waitForExistence(timeout: 12),
            "No source reached the not-answering state. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label))"
        )
        hold(2)
        shutter(app, named: "settings-sources-reachable-and-not")
    }

    /// One source's page: what it is, when it last answered, and what can be done to it.
    ///
    /// An OPDS catalogue rather than a folder, because a folder's page has no sign-in, no
    /// last-sync and no error to state — three of the five rows this screen exists for.
    func testCaptureSettingsSourceDetail() throws {
        guard MockCatalogues.areRunning() else {
            throw XCTSkip(
                "The mock catalogues are not running, so this walk would photograph an "
                    + "unreachable source under a name saying it is reachable."
            )
        }
        // **Injected rather than read off the device.** A simulator's registry is whoever last
        // used it, so this walk photographed a different screen each week and skipped outright
        // on a device with no catalogue at all. ``MockCatalogues`` decides what it looks at.
        let app = sweepLaunch(sources: MockCatalogues.registry)
        try open("Your libraries", in: app)
        let source = try XCTUnwrap(
            control(MockCatalogues.attic, in: app)
                ?? control("StoryArc Test Catalogue", in: app)
                ?? control("Attic NAS", in: app),
            "Your libraries lists no catalogue. Cells: "
                + "\(app.cells.allElementsBoundByIndex.prefix(10).map(\.label))"
        )
        source.tap()
        XCTAssertTrue(
            app.staticTexts["Status"].waitForExistence(timeout: 5),
            "The source did not open a page stating its status."
        )
        hold(1)
        shutter(app, named: "settings-source-detail")
    }

    /// The same page at the largest accessibility text size.
    ///
    /// `source-lifecycle` §4.1 asks for this screen at both text sizes and there has never been
    /// a walk for the larger one. It is the screen with the most to lose: five rows that are
    /// each a label on the left and a value on the right, and two of the values are a date and
    /// a sentence — *No answer since Sep 5, 2026 at 15:02* already wraps to two lines at the
    /// default size, so what it does at `AccessibilityXXXL` is the question.
    ///
    /// A method rather than a flag, following `testCaptureSettingsRootAtLargestText`: the
    /// content size is a launch argument, so it cannot be varied within a run.
    func testCaptureSettingsSourceDetailAtLargestText() throws {
        guard MockCatalogues.areRunning() else {
            throw XCTSkip("The mock catalogues are not running, so no source here is reachable.")
        }
        let app = sweepLaunch(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            sources: MockCatalogues.registry
        )
        try open("Your libraries", in: app)
        let source = try XCTUnwrap(
            control(MockCatalogues.attic, in: app)
                ?? control("StoryArc Test Catalogue", in: app)
                ?? control("Attic NAS", in: app),
            "Your libraries lists no catalogue. Cells: "
                + "\(app.cells.allElementsBoundByIndex.prefix(10).map(\.label))"
        )
        source.tap()
        XCTAssertTrue(
            app.staticTexts["Status"].waitForExistence(timeout: 5),
            "The source did not open a page stating its status."
        )
        hold(1)
        shutter(app, named: "settings-source-detail-ax5")
    }

    /// Pull to refresh, after it has finished.
    ///
    /// `source-lifecycle` §4.4 asks for this gesture mid-way and settled. **The settled half is
    /// this walk; the mid-gesture half is a recording**, for the reason `CurlWalkTests` records
    /// at length: `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` returns
    /// after the whole gesture, the lift included, so a shutter after it photographs a settled
    /// screen. That mistake was made once in this repository and read as a shader defect before
    /// the arithmetic gave the harness away.
    ///
    /// What settled looks like is the sentence at the foot: *Libraries checked just now.* It is
    /// the refresh indicator's own completion state, and a frame of a spinner cannot show it.
    ///
    /// The gesture is a slow drag rather than `swipeDown()`, so the refresh is actually
    /// triggered rather than the shelf merely scrolling: a fast swipe on a shelf already at the
    /// top does nothing a reader would call a refresh.
    func testCapturePullToRefreshSettled() throws {
        guard MockCatalogues.areRunning() else {
            throw XCTSkip("The mock catalogues are not running, so a refresh has nothing to ask.")
        }
        let app = sweepLaunch(sources: MockCatalogues.registry)
        try showTheShelf(in: app)
        pullToRefresh(in: app)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Libraries checked")
            ).firstMatch.waitForExistence(timeout: 20),
            "The shelf never said it had checked. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label))"
        )
        hold(1)
        shutter(app, named: "library-pull-to-refresh-settled")
    }

    /// The sheet a reader is sent back to when a server has stopped accepting their key.
    ///
    /// `source-lifecycle` §4.2: the add sheet re-opened by the detail screen's *Sign in again*
    /// row, with the address already filled and the secret empty. It sat open for months
    /// because the state was a race — a mock served with a rotated key answers 401 on one
    /// launch and a connection failure on the next, and only the first offers the row.
    ///
    /// ``MockCatalogues/refusedKavita`` ends the race by not using a server at all: a source
    /// whose `credentialReference` names a secret the keychain does not hold cannot build a
    /// page, and `LibrarySourceHealth` answers `.unauthorized` for exactly that. The state is
    /// the same one a refusal reaches, by the one route that cannot flicker.
    func testCaptureReconnectSheet() throws {
        try captureReconnect(contentSize: nil, named: "source-reconnect-sheet")
    }

    /// The same sheet at the largest accessibility text size, where a field label and a hint
    /// have to survive together above the keyboard.
    func testCaptureReconnectSheetAtLargestText() throws {
        try captureReconnect(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            named: "source-reconnect-sheet-ax5"
        )
    }

    private func captureReconnect(contentSize: String?, named name: String) throws {
        let app = sweepLaunch(contentSize: contentSize, sources: MockCatalogues.refusedKavita)
        try open("Your libraries", in: app)
        let source = try XCTUnwrap(
            control("Attic Kavita", in: app),
            "Your libraries lists no Kavita server. Cells: "
                + "\(app.cells.allElementsBoundByIndex.prefix(10).map(\.label))"
        )
        source.tap()
        // The state before the action, because the action is only offered for this one: a walk
        // that tapped a row without checking would pass against a source that had quietly
        // become unreachable, and photograph a sheet raised for another reason.
        XCTAssertTrue(
            app.staticTexts["Sign-in needed"].waitForExistence(timeout: 10),
            "The source did not reach the sign-in-needed state. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label))"
        )
        _ = scrollTo(app.buttons["Sign in again"], in: app, swipes: 4)
        try XCTUnwrap(
            hittable("Sign in again", in: app, timeout: 8),
            "A source needing sign-in offered no way to do it."
        ).tap()
        // The sheet carries the address it already knows. That is the whole point of the
        // route — a reader who has to retype their server address has not been reconnected,
        // they have been made to add it again.
        XCTAssertTrue(
            app.textFields["Address"].waitForExistence(timeout: 8),
            "The reconnect sheet has no address field. Fields: "
                + "\(app.textFields.allElementsBoundByIndex.map(\.value.debugDescription))"
        )
        hold(1)
        shutter(app, named: name)
    }
    /// The drag itself, held long enough at the bottom that a recording catches the spinner.
    ///
    /// `thenHoldForDuration` does not help a screenshot — see the walk above — but it does keep
    /// the indicator on screen for the frames a video pulls, which is what §4.4's mid-gesture
    /// half is taken from.
    private func pullToRefresh(in app: XCUIApplication) {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        top.press(
            forDuration: 0.1,
            thenDragTo: bottom,
            withVelocity: .slow,
            thenHoldForDuration: 1.5
        )
    }

    /// The way in, which is the one thing this shares with the settings sweep.
    private func open(_ group: String, in app: XCUIApplication) throws {
        try openSettings(in: app)
        try XCTUnwrap(control(group, in: app), "Settings has no \(group) row.").tap()
        XCTAssertTrue(
            app.navigationBars[group].waitForExistence(timeout: 5),
            "\(group) did not open a screen titled \(group). Navigation bars: "
                + "\(app.navigationBars.allElementsBoundByIndex.map(\.identifier))"
        )
        hold(0.5)
    }
}
