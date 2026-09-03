import XCTest

/// The publication page, on the three kinds of publication that make it look different.
///
/// Nothing in this repository photographs it. `AuditWalk.openFirstPublication` reaches it —
/// the accessibility audits measure it — and no capture has ever filed a picture of it, so
/// the largest single surface in the app between the shelf and the reader has no visual
/// record at all.
///
/// **Three publications, chosen for what they lack.** The page is a hero, an action, a
/// provenance line, a series shelf and a description, and every one of the last four is
/// conditional. A page with all of them tells a reviewer what it looks like when it is full;
/// only the bare ones say what the layout does with the space when it is not.
///
/// Chosen by title rather than by position, because "the first cover" is not a stable
/// identity across two launches of a shelf that can reorder between them —
/// `AuditWalk.openFirstPublication(in:named:)` exists for exactly this.
@MainActor
final class SweepDetailTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A comic with real artwork: the hero at its fullest.
    func testCaptureDetailWithCover() throws {
        let app = sweepLaunch()
        try openDetail(named: "Fine Print", in: app)
        hold(1.5)
        shutter(app, named: "detail-with-cover")
    }

    /// The same at the largest accessibility text size.
    func testCaptureDetailWithCoverAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openDetail(named: "Fine Print", in: app)
        hold(1.5)
        shutter(app, named: "detail-with-cover-ax5")
    }

    /// A publication with no cover the app could find: the hero as a well.
    ///
    /// `CoverlessWell` draws the title into the space the artwork would have taken, and the
    /// page then draws the title again underneath. Whether that reads as a considered
    /// fallback or as the same word twice is the question this frame is for.
    func testCaptureDetailWithoutCover() throws {
        let app = sweepLaunch()
        try openDetail(named: "Harbour Lights 01", in: app)
        hold(1.5)
        shutter(app, named: "detail-no-cover")
    }

    /// A publication in a series, so the *other issues* shelf is drawn.
    ///
    /// Harbour Lights has two members in the corpus; a single-issue publication draws no
    /// shelf at all, which is why this and `detail-bare` are two frames rather than one.
    func testCaptureDetailWithSeries() throws {
        let app = sweepLaunch()
        try openDetail(named: "Harbour Lights 02", in: app)
        // The series shelf is below the fold on a phone at any text size.
        _ = scrollTo(app.staticTexts["Other issues in this series"], in: app, swipes: 4)
        hold(1)
        shutter(app, named: "detail-series-shelf")
    }

    /// A publication with no series, no description and no other issue: the page at its
    /// emptiest, which is what most of a folder library looks like.
    func testCaptureDetailBare() throws {
        let app = sweepLaunch()
        try openDetail(named: "The Long Field", in: app)
        hold(1.5)
        shutter(app, named: "detail-bare")
    }

    /// The overflow menu, which is where everything that is not *open it* lives.
    func testCaptureDetailMoreActions() throws {
        let app = sweepLaunch()
        try openDetail(named: "Fine Print", in: app)
        try XCTUnwrap(hittable("More actions", in: app), "The page offers no overflow menu.").tap()
        hold(0.75)
        shutter(app, named: "detail-more-actions")
    }

    /// Starting again from page one, confirmed.
    ///
    /// `reading-progress` restarts a finished publication deliberately, and the confirmation
    /// is where the app promises the file itself is untouched. It is one of the few
    /// destructive-sounding sentences in the app and it has no picture.
    func testCaptureDetailRestartConfirmation() throws {
        let app = sweepLaunch()
        try openDetail(named: "Fine Print", in: app)
        guard let restart = hittable("Start from the beginning", in: app)
            ?? menuEntry("Start from the beginning", in: app) else {
            throw XCTSkip(
                "This publication offers no restart — it has no recorded position yet. "
                    + "Buttons: \(app.buttons.allElementsBoundByIndex.map(\.label))"
            )
        }
        restart.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Start “")
            ).firstMatch.waitForExistence(timeout: 5),
            "Restart asked for no confirmation."
        )
        hold(0.5)
        shutter(app, named: "detail-restart-confirm")
    }

    /// An audiobook's page, whose primary action says *Listen* rather than *Read*.
    ///
    /// `PrimaryAction` carries four wordings and only two of them have ever been
    /// photographed. This is the surface that decides which a listener sees.
    func testCaptureDetailAudiobook() throws {
        let app = sweepLaunch()
        try openDetail(named: "Sea Room", in: app)
        hold(1.5)
        shutter(app, named: "detail-audiobook")
    }

    // MARK: - The walk

    /// Opens one publication by name and proves the page is up.
    ///
    /// The primary action is the landmark, for `AuditWalk`'s reason: it is the one element
    /// only this page has, and a walk that photographed the shelf under a filename saying
    /// *detail* has already happened in this repository once.
    private func openDetail(named title: String, in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        let cover = try find(title, in: app)
        cover.tap()
        XCTAssertTrue(
            app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 10),
            "Opening “\(title)” reached no page with a way in. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(15).map(\.label))"
        )
    }

    /// The cover whose spoken label begins with this title, scrolling to find it.
    ///
    /// A cover's label carries the title, then the subtitle, the format and the progress —
    /// see `AuditWalk.shelfIdentity(of:endingWith:)` — so the title is a prefix rather than
    /// the whole label. The shelf is a lazy grid, so a cover below the fold does not exist
    /// rather than existing off-screen.
    private func find(_ title: String, in app: XCUIApplication) throws -> XCUIElement {
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        for _ in 0..<8 {
            if let hit = wanted.allElementsBoundByIndex.first(where: \.isHittable) { return hit }
            app.swipeUp()
        }
        throw XCTSkip("This device's shelf never showed a cover for “\(title)”.")
    }

    /// The same control, when it is a row inside the overflow menu rather than on the page.
    private func menuEntry(_ name: String, in app: XCUIApplication) -> XCUIElement? {
        guard let more = hittable("More actions", in: app) else { return nil }
        more.tap()
        return hittable(name, in: app)
    }
}
