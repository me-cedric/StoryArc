import XCTest

/// The iPad's two panes: the shelf, and the page beside it.
///
/// `publication-detail` asks for three things a screenshot alone cannot settle, so each walk
/// here photographs *and* asserts:
///
/// - *Two panes* — "the page appears beside the library, **which stays visible and usable**".
///   A frame of a page proves nothing about the shelf; a frame of a page with covers still
///   hittable behind the assertion does.
/// - *The pane before anything is chosen* — "the second pane says so in one sentence rather
///   than showing an arbitrary publication or an empty rectangle".
/// - *Choosing another cover* — "replaces the page's contents without the library scrolling
///   or losing its place".
///
/// **What this suite cannot take, and nobody should pretend otherwise.** Split View beside a
/// second app is not scriptable from `XCUIApplication`: it needs the app switcher and a drag
/// between two apps, which XCUITest has no vocabulary for. The narrow-then-widen path has the
/// same problem. Both are named in the handoff as manual captures, with the sequence they
/// have to show, exactly as `one-library-three-destinations` task 4.3 names Android's.
///
/// Run with `--device` pointed at an iPad. Every walk skips on a compact window rather than
/// filing a phone's frames under an iPad's name.
@MainActor
final class SweepIpadPaneTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // Put the device back. An orientation is device state, and the next suite's phone
        // frames would be landscape without this.
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// The second pane before a publication has been chosen, in landscape.
    ///
    /// The frame `publication-detail` task 4.3 has owed iOS since the day it was written, and
    /// could not be taken because there was no second pane to put a sentence in. What it has
    /// to show is the sentence — not an arbitrary publication, and not an empty rectangle.
    func testCaptureIpadEmptyPane() throws {
        let app = try landscape()
        try go(to: "Library", in: app)
        hold(2.5)
        try assertTheSentenceIsInThePane(of: app)
        shutter(app, named: "ipad-empty-pane")
    }

    /// The same, portrait, which is the narrow half of the pane question.
    ///
    /// An 11-inch iPad is 834 points wide in portrait — a *regular* size class, so the split
    /// does not collapse, and both panes are drawn in a window that a phone's worth of shelf
    /// and a phone's worth of page have to share. That is the frame that says whether 320 is
    /// the right floor for the shelf column.
    func testCaptureIpadEmptyPanePortrait() throws {
        let app = try portrait()
        try go(to: "Library", in: app)
        hold(2.5)
        try assertTheSentenceIsInThePane(of: app)
        shutter(app, named: "ipad-empty-pane-portrait")
    }

    /// A cover chosen, and the shelf still there beside it.
    ///
    /// **The assertion is the shelf, not the page.** ``SweepIpadTests/testCaptureIpadDetail``
    /// already photographs a page reached from a cover, and passed for weeks against a layout
    /// that pushed the page *over* the shelf — a screenshot of a page is the same picture
    /// either way. What tells the two apart is whether a second cover is still on screen and
    /// still hittable once the page is up.
    func testCaptureIpadPageBesideTheShelf() throws {
        let app = try landscape()
        try go(to: "Library", in: app)
        hold(2.5)
        let covers = realCovers(in: app)
        try XCTSkipUnless(covers.count >= 2, "This iPad's shelf drew fewer than two covers.")
        let second = covers[1].label
        covers[0].tap()
        XCTAssertTrue(
            app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 10),
            "The cover reached no publication page."
        )
        hold(2)
        XCTAssertFalse(
            coversOnScreen(in: app, named: second).isEmpty,
            """
            The shelf is gone. publication-detail requires the page to appear beside the \
            library, "which stays visible and usable" — so \(second), which was beside the \
            cover that was tapped, has to still be on screen. It is not, which means the page \
            was pushed over the shelf rather than put in the second pane.
            """
        )
        shutter(app, named: "ipad-page-beside-shelf")
    }

    /// A second cover replaces the page's contents, and the shelf does not move.
    ///
    /// The clause is "choosing another cover replaces the page's contents **without the
    /// library scrolling or losing its place**", and the shelf's own frame is what says so:
    /// a layout that pushed and popped would have moved it.
    func testCaptureIpadSecondChoiceKeepsTheShelfStill() throws {
        let app = try landscape()
        try go(to: "Library", in: app)
        hold(2.5)
        let covers = realCovers(in: app)
        try XCTSkipUnless(covers.count >= 2, "This iPad's shelf drew fewer than two covers.")
        let second = covers[1]
        let secondName = second.label
        let before = second.frame

        covers[0].tap()
        XCTAssertTrue(
            app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 10),
            "The first cover reached no publication page."
        )
        hold(1.5)
        let stillThere = coversOnScreen(in: app, named: secondName)
        try XCTSkipUnless(
            !stillThere.isEmpty,
            "\(secondName) left the shelf when the first cover was chosen — "
                + "testCaptureIpadPageBesideTheShelf is the walk that reports that."
        )
        stillThere[0].tap()
        hold(2)

        let after = coversOnScreen(in: app, named: secondName)
        XCTAssertFalse(after.isEmpty, "\(secondName) left the shelf when it was chosen.")
        // Two points of tolerance: a pane animating in can nudge a column's layout by a
        // sub-point and the comparison should not be about rounding.
        XCTAssertEqual(
            after[0].frame.midY,
            before.midY,
            accuracy: 2,
            """
            The shelf moved when a second cover was chosen — \(secondName) was at \
            \(Int(before.midY)) and is now at \(Int(after[0].frame.midY)). The page's \
            contents are meant to be replaced without the library scrolling or losing its \
            place.
            """
        )
        shutter(app, named: "ipad-second-choice")
    }

    /// The sentence, wherever the platform put the pane.
    ///
    /// Asked of the whole window rather than of a located pane: XCUITest has no notion of a
    /// split view's columns, and a walk that tried to find one by frame arithmetic would be
    /// asserting this suite's guess about a layout rather than the layout.
    private func assertTheSentenceIsInThePane(of app: XCUIApplication) throws {
        let sentence = "Choose a cover to see what it is and where it came from."
        XCTAssertTrue(
            app.staticTexts[sentence].waitForExistence(timeout: 8),
            """
            The second pane does not carry the empty-pane sentence. Texts on screen: \
            \(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))
            """
        )
    }
}
