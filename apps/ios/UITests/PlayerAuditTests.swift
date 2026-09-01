import XCTest

/// The player, under the platform's own accessibility audit.
///
/// `audio-playback`'s third requirement is that "every playback control SHALL be operable by
/// assistive technology, and the surface SHALL be usable at the largest text size", and until
/// now nothing on either platform had checked the player against a tool rather than against a
/// reading of the code. `PlayerLabelsTests` asserts *what* each control decides to announce;
/// this asks the system whether the elements those decisions land on are reachable at all.
///
/// It **reports and does not fail**, for the reason `AuditWalk.reportOnly(_:named:)` sets out
/// at length: one `XCTExpectFailure` broad enough to absorb the known contrast findings under
/// the glass chrome is broad enough to absorb a navigation failure too, silently, and it did
/// exactly that once. So the walk asserts and the audit prints. What can fail here is failing
/// to *reach* the player.
///
/// Its own file rather than more of `AccessibilityAuditTests`: every test here needs an
/// audiobook on the device's shelf, which none of that file's eight screens do.
@MainActor
final class PlayerAuditTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The shelf with the compact bar on it.
    ///
    /// `audio-playback`: the bar is "announced as one element naming what is playing, with its
    /// play/pause action and its open action reachable separately". The audit cannot check
    /// *that* — it is one shape among several the platform accepts — but it does check that
    /// nothing in the bar is an unlabelled control, which is the failure the other platform's
    /// gate exists to catch and the one a row of glyphs produces.
    func testCompactBarPassesTheAudit() throws {
        let app = launch()
        try openAnAudiobook(in: app)
        try reportOnly(app, named: "Library with the compact bar")
    }

    /// The full player, at the default text size.
    func testFullPlayerPassesTheAudit() throws {
        let app = launch()
        try openAnAudiobook(in: app)
        try openThePlayer(in: app)
        try reportOnly(app, named: "Player")
    }

    /// And at the largest accessibility text size, which is the other half of the
    /// requirement: "no transport control is pushed off the screen".
    ///
    /// An audit is not a layout check and will not say whether the transport is on screen —
    /// `after-2026-09-01-ios-player/ios-full-player-largest-text.png` is what says that. What
    /// this adds is whether anything becomes unreachable at that size, which a picture cannot
    /// show.
    func testFullPlayerPassesTheAuditAtLargestText() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openAnAudiobook(in: app)
        try openThePlayer(in: app)
        try reportOnly(app, named: "Player (AccessibilityXXXL)")
    }

    /// The three sheets the player opens, which are three more surfaces than the captures
    /// cover.
    ///
    /// The chapter list is the interesting one: every row is a glyph, a name and a duration
    /// combined into one element, and *selected* is a trait rather than a word — so a row that
    /// had lost its label would be an unlabelled button, which is precisely what an audit
    /// finds.
    func testTheChapterListPassesTheAudit() throws { try auditSheet(named: "Chapters") }

    func testTheSpeedSheetPassesTheAudit() throws { try auditSheet(named: "Speed") }

    func testTheSleepTimerSheetPassesTheAudit() throws { try auditSheet(named: "Sleep timer") }

    /// Walks to one of the player's three sheets and audits it.
    ///
    /// **One test per sheet, and a fresh walk for each, because closing them is not uniform.**
    /// The first version opened all three in a loop and it did not survive the attempt:
    /// `ChapterListView` carries an explicit *Close* and `SpeedSheet` and `SleepTimerSheet`
    /// carry none — they are `.medium` detents a reader drags away or dismisses by choosing a
    /// row — and `app.buttons["Close"].firstMatch` bound to the **player's** Close behind the
    /// chapter sheet, closing the player instead. The loop then reported that the player
    /// offered no speed control, which was true of the shelf it was looking at and false of
    /// the app.
    ///
    /// Three sheets on one surface behaving three ways is the kind of inconsistency a
    /// screen-reader user meets first. Nothing in `audio-playback` requires a close control,
    /// so it is recorded here rather than changed.
    ///
    /// The name is the label `PlayerText` gives the control — *Speed* rather than the `1×` on
    /// its face, which is its *value*. A control announced by its value alone is exactly what
    /// `audio-playback`'s "a name and, where it carries one, its value" rules out.
    private func auditSheet(named sheet: String) throws {
        let app = launch()
        try openAnAudiobook(in: app)
        try openThePlayer(in: app)

        guard let control = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", sheet)
        ).allElementsBoundByIndex.first(where: \.isHittable) else {
            XCTFail(
                "The player offers no \(sheet) control. Buttons on screen: "
                    + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
            )
            return
        }
        control.tap()
        try reportOnly(app, named: "Player > \(sheet)")
    }

    /// Opens the full player from the compact bar.
    private func openThePlayer(in app: XCUIApplication) throws {
        let wayIn = try XCTUnwrap(app.buttons["Open the player"].firstMatch)
        XCTAssertTrue(wayIn.waitForExistence(timeout: 5), "The bar offered no way into the player.")
        wayIn.tap()
        XCTAssertTrue(
            app.buttons["Close"].firstMatch.waitForExistence(timeout: 5),
            "The player never appeared."
        )
    }
}
