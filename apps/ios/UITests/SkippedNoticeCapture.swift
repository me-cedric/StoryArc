import XCTest

/// Photographs the notice that says which publications could not be opened.
///
/// An extension rather than more methods in `ScreenshotTests.swift`, which is at the length
/// the linter warns at. `capture-ios.mjs` runs the whole class, so these are picked up
/// wherever they are declared.
///
/// **The device needs two files that fail differently.** `node scripts/corpus.mjs
/// --simulator` writes them: `Sealed Archive.cb7` is a container StoryArc does not read, and
/// `Locked Vault.cbz` is a ZIP it reads and cannot decrypt. One refused file would show the
/// notice naming a publication, which is worth photographing — but it could not show the
/// count leading to a list of two different reasons, which is the thing the spec forbids
/// merging. These captures skip rather than lie if the corpus is not there.
extension ScreenshotTests {

    /// The library with the notice on it, at the default text size.
    func testCaptureSkippedNotice() throws {
        let app = launch()
        try showTheNotice(in: app)
        attach(app.screenshot(), named: "skipped-notice")
    }

    /// The same, at the largest accessibility text size.
    ///
    /// This is the size the layout was rebuilt for. The first version of the banner put the
    /// two labelled controls in a row beside the sentence, and a row measures its unweighted
    /// children first — on Android that laid the sentence out at zero width, which is a
    /// defect a picture at the default size would never have shown.
    func testCaptureSkippedNoticeAtLargestText() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try showTheNotice(in: app)
        attach(app.screenshot(), named: "skipped-notice-ax5")
    }

    /// The list behind the notice: every publication, with its own reason.
    ///
    /// The reasons are the point. The count the notice replaced could not carry one, and the
    /// spec forbids the two being merged into a single sentence — so a picture with two
    /// different reasons in it is the proof that they are not.
    func testCaptureSkippedList() throws {
        let app = launch()
        try showTheNotice(in: app)
        let wayIn = app.buttons["What couldn’t be opened"].firstMatch
        XCTAssertTrue(
            wayIn.waitForExistence(timeout: 5),
            "The notice offered no named control leading to the list."
        )
        wayIn.tap()
        _ = app.collectionViews.firstMatch.waitForExistence(timeout: 5)
        attach(app.screenshot(), named: "skipped-list")
    }

    /// Library, with the notice actually on screen before anything is photographed.
    ///
    /// `AuditWalk` makes the argument at length and it applies here twice over: a capture
    /// that can silently photograph the screen behind the one it names is worth less than no
    /// capture, and this one's whole subject is a strip that is absent on a device with a
    /// clean library. So it asserts the notice exists, and skips with an instruction when the
    /// corpus is missing rather than filing a picture of a shelf.
    fileprivate func showTheNotice(in app: XCUIApplication) throws {
        try XCTUnwrap(destination("Library", in: app)).tap()
        // The shelf first, for the reason every capture here waits for it: tapping a tab is
        // instant and decoding covers is not.
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)

        let wayIn = app.buttons["What couldn’t be opened"].firstMatch
        guard wayIn.waitForExistence(timeout: 20) else {
            throw XCTSkip(
                "No skipped-publications notice on this device. Run "
                    + "`node scripts/corpus.mjs --simulator` — it writes the two files that "
                    + "fail differently, Sealed Archive.cb7 and Locked Vault.cbz."
            )
        }
    }
}
