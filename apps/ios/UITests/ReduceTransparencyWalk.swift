import XCTest

/// The reader's glass chrome and its theme sheet under **Reduce Transparency**, photographed
/// beside a control with the setting off.
///
/// `reader-theming-and-page-transitions` 7.6: with Reduce Transparency on, the glass is
/// replaced by an opaque fill and a strong border (`Glass.swift`). The unit tests assert the
/// rule; what they cannot say is that the setting reaches the reader's own chrome and the sheet
/// over the page. `simctl ui` has no switch for it, so `setDisplaySwitch` drives Settings.
///
/// Run each with `scripts/capture-ios.mjs --appearance light` and `--appearance dark`.
@MainActor
final class ReduceTransparencyWalkTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCaptureReaderChromeStandard() throws { try walk(reduced: false) }

    func testCaptureReaderChromeReduced() throws { try walk(reduced: true) }

    private func walk(reduced: Bool) throws {
        let name = reduced ? "reduced" : "standard"
        if reduced {
            try setDisplaySwitch("Reduce Transparency", on: true)
            addTeardownBlock { @MainActor in try? self.setDisplaySwitch("Reduce Transparency", on: false) }
        }
        let app = sweepLaunch(freshShelfSettings: true)
        try XCTSkipUnless(
            openReflowableBook(named: "The Long Field", in: app),
            "This device's shelf never opened a reflowable book."
        )
        // The chrome is up for a few seconds after a book opens: that is the frame.
        hold(1)
        shutter(app, named: "ios-reader-chrome-\(name)")

        let menu = app.buttons["Menu"].exists ? app.buttons["Menu"] : revealed("Menu", in: app)
        try XCTUnwrap(menu, "The reader revealed no menu to open.").tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 8), "The reader menu did not open.")
        hold(1)
        shutter(app, named: "ios-reader-menu-\(name)")

        for _ in 0..<5 where hittableRow("Reading themes", in: app, timeout: 1) == nil {
            app.swipeUp()
            hold(0.7)
        }
        try XCTUnwrap(hittableRow("Reading themes", in: app), "The menu offers no reading-themes row.").tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 8), "The theme sheet did not open.")
        hold(1)
        shutter(app, named: "ios-theme-sheet-\(name)")
    }
}
