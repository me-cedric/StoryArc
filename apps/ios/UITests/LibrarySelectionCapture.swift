import XCTest

/// Photographs the chrome a selection puts up, in the two states the change is about.
///
/// An extension rather than more methods in `ScreenshotTests.swift`, which is one line under
/// the length the linter warns at — `SkippedNoticeCapture.swift` and `AppIconCapture.swift`
/// split off for the same reason, and `capture-ios.mjs` runs the whole class, so these are
/// picked up wherever they are declared.
///
/// **`testCaptureLibrarySelectingAtTheEnd`, in `ScreenshotTests`, is not enough on its own.**
/// It photographs the mode with nothing picked and the shelf scrolled to its end, which is
/// the frame that settles the inset — and the inset was never the defect. What was wrong was
/// the shape: a full-bleed grey slab with a hard top edge, holding a count and a *Done* and
/// three bare glyphs, stacked above the rounded glass tab bar. Two bottom bars at once. So
/// these two walks photograph the parts that walk cannot:
///
/// - the capsule **live**, with covers picked, at the top of the shelf, where the tab bar's
///   absence is visible and the count is in the navigation bar instead;
/// - the capsule at the **largest accessibility text size**, which is the only thing that can
///   say which branch of the `ViewThatFits` in `BulkActionBar` a real phone takes.
extension ScreenshotTests {

    /// The shelf in selection mode with something actually picked.
    ///
    /// Inert chrome says nothing about what the chrome looks like when it is doing its job,
    /// and the walk in `ScreenshotTests` catches it inert. This one picks two covers first —
    /// two, so the count in the navigation bar is a plural in every language — and stays at
    /// the top of the shelf. What should be at the foot of the screen is one floating capsule
    /// with the shelf showing either side of it, where a grey slab used to sit on a glass
    /// pill.
    func testCaptureLibrarySelectingWithPicks() throws {
        let app = launch()
        try pickTwo(in: app)
        attach(app.screenshot(), named: "library-selecting-picked")
    }

    /// The same, at the largest accessibility text size.
    ///
    /// **This is the capture the `ViewThatFits` in `BulkActionBar` exists for**, and the only
    /// thing that can settle it. Each action is named — *Add to…*, *Download*, *Mark as
    /// read* — wherever the width holds all three, and gives way to its glyph where it does
    /// not. A host test can prove the fallback is declared; it cannot prove which branch a
    /// phone at `accessibility-extra-extra-extra-large` takes, in a language whose words are
    /// longer again. Three glyphs in this frame means the fallback is doing real work and the
    /// names are still there for VoiceOver. Clipped text means the capsule is wrong.
    func testCaptureLibrarySelectingAtLargestText() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try pickTwo(in: app)
        attach(app.screenshot(), named: "library-selecting-ax5")
    }

    /// Enters selection mode on the shelf and picks the first two covers.
    ///
    /// The covers are taken by index inside the shelf rather than by title: the corpus a
    /// device happens to hold decides the titles, and this walk is about the chrome rather
    /// than about which publication is in it.
    private func pickTwo(in app: XCUIApplication) throws {
        try XCTUnwrap(destination("Library", in: app)).tap()
        let shelf = app.scrollViews.firstMatch
        _ = shelf.waitForExistence(timeout: 10)
        try XCTUnwrap(app.buttons["Select"].firstMatch).tap()
        XCTAssertTrue(
            app.buttons["Done"].waitForExistence(timeout: 5),
            "Tapping Select did not put the shelf into selection mode."
        )
        let covers = shelf.buttons
        let picking = min(covers.count, 2)
        for index in 0..<picking { covers.element(boundBy: index).tap() }
        XCTAssertGreaterThan(
            picking,
            0,
            "The shelf offered no cover to pick, so the capsule would be photographed inert."
        )
        pause()
    }

    /// A second for the chrome to settle before the shutter.
    ///
    /// `ScreenshotTests.settle(_:)` does the same thing and is `private`, which is
    /// file-scoped in Swift and so out of reach here. A second copy is cheaper than widening
    /// that one: the walks in this file are the only callers, and `SkippedNoticeCapture`
    /// needed no wait at all.
    private func pause() {
        let settled = XCTestExpectation(description: "the selection's chrome settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 4)
    }
}
