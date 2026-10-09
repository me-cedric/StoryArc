import XCTest

/// Wave 5 iPad frames: portrait Downloads and Search, the library with its sidebar in both
/// orientations, Settings on a 13-inch iPad, and a page chosen beside the shelf in portrait.
///
/// Run through `/tmp/w5hs` host shots (see ``XCTestCase/hostShot(_:)``): a landscape iPad's
/// own screenshot is rotated and cropped on a headless simulator.
@MainActor
final class SweepWave5IpadTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// `one-library-three-destinations` 1.2: Downloads in portrait, something on the device.
    func testCaptureDownloadsPortrait() throws {
        let app = try portrait()
        try go(to: "Downloads", in: app)
        hold(3)
        shutter(app, named: "ipad-portrait-downloads")
    }

    /// `one-library-three-destinations` 1.2: Search at rest in portrait.
    func testCaptureSearchPortrait() throws {
        let app = try portrait()
        try go(to: "Search", in: app)
        hold(3)
        shutter(app, named: "ipad-portrait-search")
    }

    /// `one-library-three-destinations` 4.1: the library with its sidebar, portrait.
    func testCaptureLibrarySidebarPortrait() throws {
        let app = try portrait()
        try go(to: "Library", in: app)
        hold(2)
        try? showSidebar(in: app)
        hold(2)
        shutter(app, named: "ipad-portrait-library-sidebar")
    }

    /// `one-library-three-destinations` 4.1: the library with its sidebar, landscape.
    func testCaptureLibrarySidebarLandscape() throws {
        let app = try landscape()
        try go(to: "Library", in: app)
        hold(3)
        shutter(app, named: "ipad-landscape-library-sidebar")
    }

    /// `one-library-three-destinations` 4.1: Settings on a 13-inch iPad, landscape, where the
    /// 720 pt measure shows.
    func testCaptureSettingsLandscape() throws {
        let app = try landscape()
        try go(to: "Home", in: app)
        hold(2)
        try openSettings(in: app)
        hold(2)
        shutter(app, named: "ipad-landscape-settings")
    }

    /// `one-library-three-destinations` 4.1: Settings in portrait.
    func testCaptureSettingsPortrait() throws {
        let app = try portrait()
        try go(to: "Home", in: app)
        hold(2)
        try openSettings(in: app)
        hold(2)
        shutter(app, named: "ipad-portrait-settings")
    }

    /// `publication-detail` 4.1: portrait with both panes, a page chosen.
    func testCapturePageChosenPortrait() throws {
        let app = try portrait()
        try go(to: "Library", in: app)
        hold(3)
        let covers = realCovers(in: app)
        try XCTSkipUnless(!covers.isEmpty, "The shelf drew no cover.")
        covers[0].tap()
        XCTAssertTrue(
            app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 10),
            "The cover reached no publication page."
        )
        hold(2.5)
        shutter(app, named: "ipad-portrait-page-chosen")
    }
}
