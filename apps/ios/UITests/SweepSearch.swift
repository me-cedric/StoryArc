import XCTest

/// The search destination, in the four states it has.
///
/// `ScreenshotTests` photographs it at rest and at rest again at the largest text size, and
/// that is all iOS has ever had. What a *query* does to this screen — the grouped results, the
/// notice a silent source puts up, the sentence when nothing matched, and the axis narrowed to
/// this device — has never been photographed at all.
///
/// **The term arrives as a launch argument rather than through the keyboard.** Typing into the
/// simulator goes through a French layout and garbles ASCII, which this repository has paid
/// for twice; and a restored term runs exactly as a typed one, because
/// `LibrarySearchSurface` asks on `.onChange(of: model.query.search, initial: true)` rather
/// than on submission. The field draws it either way — it is bound to the same value.
@MainActor
final class SweepSearchTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The screen a reader lands on: the scope, the recent searches, and three suggestion
    /// shelves that are each drawn only when they have something in them.
    func testCaptureSearchAtRest() throws {
        let app = sweepLaunch()
        try showSearch(in: app)
        hold(1.5)
        shutter(app, named: "search-at-rest")
    }

    /// The same at the largest accessibility text size, where *Next in a series you have read*
    /// is a sentence rather than a word.
    func testCaptureSearchAtRestAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try showSearch(in: app)
        hold(1.5)
        shutter(app, named: "search-at-rest-ax5")
    }

    /// A term with answers: results grouped by why they matched.
    ///
    /// `library-browsing` asks for results "grouped by match kind — series, publication,
    /// person, tag", and `MatchHeading` is what names each group. Whether four headings over
    /// short runs of covers reads as one answer or as four is the design question here.
    func testCaptureSearchWithResults() throws {
        let app = sweepLaunch(search: "harbour")
        try showSearch(in: app)
        XCTAssertTrue(
            app.staticTexts["Titles"].waitForExistence(timeout: 10)
                || app.staticTexts["Series"].waitForExistence(timeout: 2),
            "A term with matches produced no grouped results. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        hold(2)
        shutter(app, named: "search-results")
    }

    /// The same at the largest accessibility text size.
    func testCaptureSearchWithResultsAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL", search: "harbour")
        try showSearch(in: app)
        hold(2.5)
        shutter(app, named: "search-results-ax5")
    }

    /// A term nothing matches.
    ///
    /// Two things are in this frame and only one of them is the sentence: the device carries
    /// two servers that are not running, so the *could not answer* notice is up beside it.
    /// That pairing is a real state and a reader meets it on every train.
    func testCaptureSearchWithNoResults() throws {
        let app = sweepLaunch(search: "vermillion")
        try showSearch(in: app)
        XCTAssertTrue(
            app.staticTexts["Nothing matches “vermillion”."].waitForExistence(timeout: 15),
            "A term with no matches produced no empty sentence. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        shutter(app, named: "search-no-results")
    }

    /// The axis narrowed to what opens with no network.
    ///
    /// `library-browsing`: narrowing to the device "removes that notice, because nothing is
    /// then being waited for". The picture is the pair with `search-no-results` — the same
    /// term, one axis apart — and it is the only way to see that the notice is gone rather
    /// than merely late.
    func testCaptureSearchOnThisDevice() throws {
        let app = sweepLaunch(search: "vermillion", searchScope: "onThisDevice")
        try showSearch(in: app)
        hold(3)
        shutter(app, named: "search-on-this-device")
    }

    /// The scope control on the screen at rest, set to this device.
    ///
    /// The screen states the scope as a segmented picker *and* the field carries the
    /// platform's own scope bar, because the platform draws its bar only once the field is
    /// active — measured, in `SearchAtRest`'s own comment. This is that statement, set.
    func testCaptureSearchAtRestOnThisDevice() throws {
        let app = sweepLaunch(searchScope: "onThisDevice")
        try showSearch(in: app)
        hold(1.5)
        shutter(app, named: "search-at-rest-on-this-device")
    }

    /// Search, on screen, proved to be search.
    private func showSearch(in app: XCUIApplication) throws {
        try XCTUnwrap(destination("Search", in: app), "The shell offers no Search tab.").tap()
        // The field is the one thing every state of this screen has. Waiting for the scroll
        // view instead would pass on the shelf behind a tab that never changed.
        XCTAssertTrue(
            app.searchFields.firstMatch.waitForExistence(timeout: 10)
                || app.otherElements["Search"].waitForExistence(timeout: 2),
            "Tapping Search did not open a screen with a search field on it."
        )
    }
}
