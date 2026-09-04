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
        let app = sweepLaunch()
        try showSearch(in: app)
        try run("Harbour", in: app)
        XCTAssertTrue(
            app.staticTexts["Titles"].waitForExistence(timeout: 15)
                || app.staticTexts["Series"].waitForExistence(timeout: 3),
            "A term with matches produced no grouped results. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        hold(2)
        shutter(app, named: "search-results")
    }

    /// The same at the largest accessibility text size.
    func testCaptureSearchWithResultsAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try showSearch(in: app)
        try run("Harbour", in: app)
        hold(3)
        shutter(app, named: "search-results-ax5")
    }

    /// A term nothing matches.
    ///
    /// Two things are in this frame and only one of them is the sentence: the device carries
    /// two servers that are not running, so the *could not answer* notice is up beside it.
    /// That pairing is a real state and a reader meets it on every train.
    func testCaptureSearchWithNoResults() throws {
        let app = sweepLaunch()
        try showSearch(in: app)
        try run("Vermillion", in: app)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Nothing matches")
            ).firstMatch.waitForExistence(timeout: 20),
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
        let app = sweepLaunch(searchScope: "onThisDevice")
        try showSearch(in: app)
        try run("Vermillion", in: app)
        hold(4)
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

    /// Runs a term the way a reader would, without touching the keyboard.
    ///
    /// **An injected query cannot carry a term.** `LibraryPreferences.query()` clears `search`
    /// on restore, deliberately — "a filter is a decision that outlives a session; a
    /// half-typed search is not" — so the first version of these walks photographed the
    /// at-rest screen under filenames saying *results* and *no results*, and passed until an
    /// assertion was put on the results themselves.
    ///
    /// A recent search is a control that writes straight to `model.query.search`, which is
    /// the value the field is bound to and the value `LibrarySearchSurface` asks on. So this
    /// is the same event as typing, minus the layout that garbles ASCII. The terms are
    /// injected by ``sweepLaunch(contentSize:appearance:natural:downloads:language:searchScope:availability:layout:recents:)``,
    /// whose own comment says why the query cannot carry one.
    private func run(_ term: String, in app: XCUIApplication) throws {
        try XCTUnwrap(
            hittable(term, in: app, timeout: 8),
            "The search screen offers no recent search called “\(term)”. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
        ).tap()
        // A tap that missed leaves the at-rest screen up, and every state of this screen is a
        // plausible picture of it — so this proves the screen *changed*. The field's own value
        // would prove it too, and this is the sturdier of the two: it holds when the field is
        // cleared by a walk that never typed, and it fails loudly the day a recent search
        // stops asking. *Recent searches* is the at-rest screen's own heading, and the results
        // screen does not draw it.
        XCTAssertTrue(
            app.staticTexts["Recent searches"].waitForNonExistence(timeout: 8),
            "Tapping “\(term)” left the at-rest screen up, so the results were never asked for."
        )
    }

    /// The field itself, asserted rather than photographed.
    ///
    /// **A capture that photographs an empty screen still passes, and one did.** Every walk
    /// in this file is a `shutter`, and for two days the frames they filed under
    /// `search-at-rest` were pictures of a search screen with nothing to type in. This test
    /// exists so that state is a red test rather than a picture somebody has to look at: it
    /// names the field, its prompt, and the fact that the navigation bar is what holds it.
    ///
    /// The bar, specifically, because a field drawn in the *content* would satisfy
    /// `app.searchFields` while being a different control in a different place —
    /// ``SearchAtRest`` draws its own scope picker exactly that way, and the presence of that
    /// picker is what made the missing field survive a sweep. `library-browsing`'s *Typing a
    /// query* has no meaning without this element.
    func testSearchOffersAFieldToTypeIn() throws {
        let app = sweepLaunch()
        try showSearch(in: app)
        let field = app.navigationBars.searchFields.firstMatch
        XCTAssertTrue(
            field.waitForExistence(timeout: 10),
            "The Search screen's navigation bar holds no search field. Search fields anywhere: "
                + "\(app.searchFields.count). On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(15).map(\.label))"
        )
        XCTAssertTrue(field.isHittable, "The search field is present but cannot be tapped.")
        XCTAssertEqual(
            field.placeholderValue,
            "Search",
            "The search field carries no prompt saying what it searches."
        )
    }

    /// Search, on screen, proved to be search.
    ///
    /// **Two landmarks, because each one alone has already let this screen ship broken.**
    ///
    /// The field was the only landmark until 2026-09-04, and the 2026-09-02 sweep found the
    /// *results* screen stating no scope at all — invisible to a walk that only looked for a
    /// field. So the scope statement was added. It was then made the only landmark, on the
    /// reading that the field had been taken away by the SDK; that reading was wrong. The
    /// field was taken away by this repository, in `76d43b74`, which added
    /// `.navigationBarTitleDisplayMode(selection.isActive ? .inline : .automatic)` to
    /// `LibraryView` for the selection's inline title — and at a stack root `.automatic`
    /// draws the large title while installing no search bar beneath it. Measured four ways,
    /// one variable apart, on the same iOS 26.5 runtime that drew the field on 2026-09-02:
    /// modifier absent → field; `.large` → field; `.inline` → field; `.automatic` → none.
    ///
    /// Both are asserted here now. The scope statement is on every state of this screen and
    /// belongs to no other; the field is what the screen is *for*.
    private func showSearch(in app: XCUIApplication) throws {
        try XCTUnwrap(destination("Search", in: app), "The shell offers no Search tab.").tap()
        XCTAssertTrue(
            app.buttons["Everywhere"].waitForExistence(timeout: 10),
            "Tapping Search did not open a screen stating the scope it searches. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(15).map(\.label))"
        )
        XCTAssertTrue(
            app.navigationBars.searchFields.firstMatch.waitForExistence(timeout: 10),
            "Tapping Search did not open a screen with a search field on it. Search fields "
                + "anywhere: \(app.searchFields.count). On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(15).map(\.label))"
        )
    }
}
