import XCTest

/// Home's way into the shelves list lands on the Library tab.
///
/// `navigation-shell`: a library section opened from outside the library belongs to the
/// Library destination, so the tab bar marks Library and the list is on Library's own stack.
/// The first tap after launch is the case under test. The Library tab has not been shown
/// yet, so the same tap that selects it also asks it for the shelves list.
@MainActor
final class ShelvesFromHomeTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testShelvesFromHomeLandOnTheLibraryTab() throws {
        let app = sweepLaunch()
        try XCTUnwrap(destination("Home", in: app), "The shell offers no Home tab.").tap()
        XCTAssertTrue(app.staticTexts["Home"].waitForExistence(timeout: 10), "Home did not open.")

        // A clean device has no shelves, so Home draws its one *Shelves* row. The row is a
        // plain button whose empty middle takes no tap, so the tap goes on its label.
        let label = app.staticTexts["Shelves"]
        guard scrollTo(label, in: app) else {
            return XCTFail(
                "Home offers no way into Shelves. Buttons: "
                    + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
            )
        }
        label.tap()

        XCTAssertTrue(
            app.navigationBars["Shelves"].waitForExistence(timeout: 5),
            "The first tap on Home's Shelves row did not open the shelves list."
        )
        XCTAssertTrue(
            try XCTUnwrap(destination("Library", in: app)).isSelected,
            "The shelves list opened, but the Library tab is not the selected one."
        )
    }
}
