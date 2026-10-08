import XCTest

/// Task 7.8 of `reader-theming-and-page-transitions`: where a stored position lands, and
/// where one step of text size leaves it, on `fixture.epub`.
///
/// The fixture's two chapters are forty paragraphs each. A position is put in the store by
/// `scripts/` outside the test (the walk only reads), the book is opened, and the frame is the
/// page the reader resumed on. Then one step larger is applied through the real controls, and
/// the frame is the page the reader is left on. The paragraph number at the top of each frame
/// is the measurement; the Android side is read the same way on an emulator.
@MainActor
final class ReadiumPaginationWalkTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCaptureResumeThenOneSizeStep() throws {
        let app = sweepLaunch(freshShelfSettings: true)
        try XCTSkipUnless(
            openReflowableBook(named: "Fixture Publication", in: app),
            "This device's shelf never opened the fixture."
        )
        hold(7)
        shutter(app, named: "ios-pagination-resumed")

        try XCTUnwrap(revealed("Menu", in: app), "The reader revealed no menu to open.").tap()
        for _ in 0..<5 where hittableRow("Reading themes", in: app, timeout: 1) == nil {
            app.swipeUp()
            hold(0.7)
        }
        try XCTUnwrap(hittableRow("Reading themes", in: app), "The menu offers no reading-themes row.").tap()
        let customise = app.buttons["Customise"]
        XCTAssertTrue(customise.waitForExistence(timeout: 8), "The theme sheet offers no Customise.")
        for _ in 0..<3 where !customise.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
            hold(0.7)
        }
        customise.tap()
        let larger = app.buttons["Larger"]
        XCTAssertTrue(larger.waitForExistence(timeout: 8), "The sheet offers no Larger step.")
        larger.tap()
        hold(1)
        for _ in 0..<3 {
            guard let done = hittableRow("Done", in: app, timeout: 3) else { break }
            done.tap()
            hold(1)
        }
        hold(8)
        shutter(app, named: "ios-pagination-one-step-larger")
    }
}
