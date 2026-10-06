import XCTest

/// The publication page of a publication with no artwork, before and after a cover is chosen.
///
/// `cover-for-every-publication` task 2.6. Two states, at two text sizes; the appearance is
/// the simulator's and `capture-ios.mjs --appearance` sets it, so one class answers all four
/// conditions on each state.
///
/// **`Sea Room` is the subject and the name is load-bearing.** It is the corpus's chaptered
/// audiobook, and the one publication there that carries no artwork of any kind — no embedded
/// picture, no loose image beside it — so its page is where the coverless well is drawn.
/// `AudiobookWalk` already relies on that title for the same reason.
///
/// **The "after" state is seeded from outside and is not chosen through the picker.** The
/// system photo picker runs in another process and shows the simulator's own photo library,
/// which is empty and which a UI test may not fill. What the frame has to show is the page
/// once a cover exists, so the cover is written into the app's own override store before the
/// run — see the capture note in this change's screenshot README. The picker itself is the one
/// part of this flow a frame cannot prove, which is why `CoverLadderTests` asserts the storing
/// and the cropping instead.
@MainActor
final class SweepCoverChoiceTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The well as an entry point: a glyph, a format, and the offer underneath it.
    func testCaptureCoverlessWellOffersAChoice() throws {
        let app = sweepLaunch()
        try openSeaRoom(in: app)
        shutter(app, named: "detail-coverless-well")
    }

    /// The same at the largest accessibility text size.
    func testCaptureCoverlessWellOffersAChoiceAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openSeaRoom(in: app)
        shutter(app, named: "detail-coverless-well-ax5")
    }

    /// The page once the reader has chosen a cover: the artwork, and the way to undo it.
    func testCaptureChosenCover() throws {
        let app = sweepLaunch()
        try openSeaRoom(in: app)
        shutter(app, named: "detail-chosen-cover")
    }

    /// The same at the largest accessibility text size.
    func testCaptureChosenCoverAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openSeaRoom(in: app)
        shutter(app, named: "detail-chosen-cover-ax5")
    }

    /// The shelf, then `Sea Room`, then the page.
    ///
    /// Named `Sea Room, M4B` rather than `Sea Room`: the corpus holds the same book twice,
    /// once as a file and once as a folder of parts, and only the file carries a content
    /// digest — so the folder's page says that moving it loses the cover and the file's does
    /// not. Photographing whichever the shelf drew first would make the two frames disagree
    /// about a sentence.
    ///
    /// Two taps where the shelf groups. The shelf opens under *Grouping: Series*, and two
    /// publications with one title are a group rather than a publication — so the first tap
    /// can reach a shelf of two and the book is inside it. A shelf that offered the file
    /// directly needs only the one tap, which is why this looks for the file first.
    ///
    /// The arrival is asserted on the primary action, the way `SweepDetailTests` asserts it,
    /// because that is the control every publication page has. What this change adds is
    /// asserted by `CoverlessWellOffersAChoiceTests`; the frame is here to show it.
    private func openSeaRoom(in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        guard tapSeaRoom(prefix: "Sea Room", in: app) else {
            throw XCTSkip(
                "This device's shelf never showed a cover for \u{201C}Sea Room\u{201D}."
                    + " Seed the corpus: node scripts/corpus.mjs --simulator <udid>."
            )
        }
        // A group's own cell borrows its first member's spoken label, so the tap above
        // cannot tell a group of two from the book itself. What tells them apart is what
        // arrives: a publication page carries the primary action and a group does not. The
        // corpus holds the same title three ways — a group, a folder and a file — so this
        // taps on until a page answers rather than assuming how deep the shelf put it.
        for _ in 0..<3 {
            if app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 5) {
                break
            }
            if !tapSeaRoom(prefix: "Sea Room, M4B", in: app) {
                _ = tapSeaRoom(prefix: "Sea Room", in: app)
            }
            hold(0.5)
        }
        XCTAssertTrue(
            app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 10),
            "Opening \u{201C}Sea Room\u{201D} reached no page with a way in. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(15).map(\.label))"
        )
        hold(1.5)
    }

    /// Taps the first reachable cell whose spoken label begins with `prefix`, scrolling for
    /// it. False where the shelf never drew one, which the caller decides what to do about.
    private func tapSeaRoom(prefix: String, in app: XCUIApplication) -> Bool {
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
        // `.fast`, and enough of them to cross the whole shelf: `Sea Room` is late in the
        // alphabet and at the largest text size a shelf of seventeen is several screens
        // deeper than it is at the default one. A slow swipe there crossed four of them and
        // the walk reported a title the shelf was holding as a title the shelf never drew.
        for _ in 0..<25 {
            if let hit = wanted.allElementsBoundByIndex.first(where: \.isHittable) {
                hit.tap()
                return true
            }
            app.swipeUp(velocity: .fast)
        }
        return false
    }
}
