import XCTest

/// The app as a reader meets it on the first launch: nothing added, nothing downloaded,
/// nothing to suggest.
///
/// **Every one of these needs a device with no library on it**, which the machine this project
/// is developed on does not have — the simulator has carried a corpus, an audiobook and five
/// sources since August. So this suite skips loudly rather than photographing a full library
/// under an empty name, and the folder it is run against is a simulator created for it:
///
/// ```
/// xcrun simctl create StoryArc-Sweep-Empty "iPhone 17 Pro"
/// node scripts/capture-ios.mjs --out <dir> --only SweepEmptyTests --device StoryArc-Sweep-Empty
/// ```
///
/// The first-run state is the one a designer is most often asked about and the one a
/// development device can never show, which is why it is worth a simulator of its own.
@MainActor
final class SweepEmptyTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The library with nothing in it: a sentence, and the two actions that change it.
    func testCaptureEmptyLibrary() throws {
        let app = sweepLaunch(recents: "()")
        try XCTUnwrap(destination("Library", in: app), "no Library tab").tap()
        try requireEmpty(app, landmark: "Nothing here yet")
        shutter(app, named: "empty-library")
    }

    /// The same at the largest accessibility text size.
    func testCaptureEmptyLibraryAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL", recents: "()")
        try XCTUnwrap(destination("Library", in: app), "no Library tab").tap()
        try requireEmpty(app, landmark: "Nothing here yet")
        shutter(app, named: "empty-library-ax5")
    }

    /// Home with nothing open yet.
    func testCaptureEmptyHome() throws {
        let app = sweepLaunch(recents: "()")
        try XCTUnwrap(destination("Home", in: app), "no Home tab").tap()
        hold(3)
        shutter(app, named: "empty-home")
    }

    /// Downloads with nothing on the device: one sentence and the way to the library.
    ///
    /// `offline-downloads`: with nothing downloaded the destination "says so in one sentence
    /// and offers the action that changes it".
    func testCaptureEmptyDownloads() throws {
        let app = sweepLaunch(recents: "()")
        try XCTUnwrap(destination("Downloads", in: app), "no Downloads tab").tap()
        try requireEmpty(app, landmark: "Go to your library")
        shutter(app, named: "empty-downloads")
    }

    /// Search with nothing to suggest, which offers the five ways in instead.
    func testCaptureEmptySearch() throws {
        let app = sweepLaunch(recents: "()")
        try XCTUnwrap(destination("Search", in: app), "no Search tab").tap()
        try requireEmpty(app, landmark: "Nothing to suggest yet")
        shutter(app, named: "empty-search")
    }

    /// Settings with no libraries added.
    func testCaptureEmptySources() throws {
        let app = sweepLaunch(recents: "()")
        try openSettings(in: app)
        try XCTUnwrap(control("Your libraries", in: app), "no libraries row").tap()
        try requireEmpty(app, landmark: "No libraries yet. Add a folder from your library to get started.")
        shutter(app, named: "empty-sources")
    }

    /// Settings' root on a device with nothing configured, where five of the seven summaries
    /// say *nothing yet* in five different wordings.
    func testCaptureEmptySettingsRoot() throws {
        let app = sweepLaunch(recents: "()")
        try openSettings(in: app)
        hold(1)
        shutter(app, named: "empty-settings-root")
    }

    /// That this device is genuinely bare, before anything is photographed.
    ///
    /// It skips rather than fails: a development simulator carrying a corpus is not a defect,
    /// and a suite that reported one because its fixtures were present is a suite nobody
    /// believes twice. The message says how to get a device it can use.
    private func requireEmpty(_ app: XCUIApplication, landmark: String) throws {
        let found = app.staticTexts[landmark].waitForExistence(timeout: 15)
            || app.buttons[landmark].waitForExistence(timeout: 2)
        try XCTSkipUnless(
            found,
            "This device is not bare — “\(landmark)” is not on screen, so it holds a library. "
                + "Create one with `xcrun simctl create StoryArc-Sweep-Empty \"iPhone 17 Pro\"` "
                + "and pass --device."
        )
        hold(1)
    }
}
