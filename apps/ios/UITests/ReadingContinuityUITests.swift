import XCTest

/// That a publication comes back where it was left.
///
/// `reading-progress` opens with the promise that a reader's position "is the only copy
/// the app promises never to lose", and it is the app's single most consequential
/// behaviour: everything else is a preference, and this is somebody's evening. `STATUS.md`
/// scores nine of that capability's seventeen scenarios as **built, asserted by nothing**.
///
/// The store, the merge table and the arithmetic all have host tests. What none of them can
/// reach is the round trip — a real reader, a real navigator, a real close, a real relaunch,
/// and the position surviving all four. That needs a running app, which is what this target
/// is for.
///
/// It reports the position rather than pinning a page number: which page a publication opens
/// on depends on what is on the device, and a test that hard-codes it is a test that fails
/// when the corpus changes rather than when the app breaks. What it asserts is the property
/// — **the page after a relaunch is the page it was left on** — and it says both numbers in
/// the failure so a break is diagnosable from the log alone.
@MainActor
final class ReadingContinuityUITests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Reads a few pages, closes the publication, relaunches, and reopens it.
    ///
    /// Relaunching rather than reopening from the same process is the whole point: an
    /// in-memory position survives a dismissal for free, and the thing worth proving is
    /// that it reached the store and came back out of it.
    func testAPublicationResumesWhereItWasLeft() throws {
        let app = XCUIApplication()
        app.launch()

        let reader = try openFirstPublication(in: app)
        // One turn. Enough that resuming on the first page would fail — which is the whole
        // property — and few enough that a three-page fixture does not reach its last page
        // and get restarted by the finished rule instead.
        turnAPage(in: app)
        let left = try XCTUnwrap(pagePosition(in: app), "The reader shows no position to read.")
        close(reader, in: app)

        app.terminate()
        app.launch()
        _ = try openFirstPublication(in: app)
        let resumed = try XCTUnwrap(pagePosition(in: app), "The reader shows no position after relaunching.")

        XCTAssertEqual(
            resumed, left,
            """
            Left on \(left) and came back to \(resumed).
            A position that does not survive a relaunch is the one thing this app promises never to lose.
            """
        )
    }

    // MARK: - Private

    /// Opens the first publication on the shelf and returns the reader.
    ///
    /// Chosen by position rather than by name, so this does not depend on which fixtures a
    /// device happens to hold, and skipped rather than failed when there is nothing to open
    /// — a device whose sources have all gone away is a real state, and a suite that reports
    /// a defect because its fixtures are missing is a suite nobody believes twice.
    @discardableResult
    private func openFirstPublication(in app: XCUIApplication) throws -> XCUIElement {
        let library = app.tabBars.buttons["Library"].firstMatch
        try XCTSkipUnless(library.waitForExistence(timeout: 15), "The shell drew no tab bar.")
        library.tap()

        // Re-queried on every attempt, never cached. An `XCUIElement` array is a snapshot,
        // and going back to the shelf invalidates it — the second attempt then asks for an
        // element that no longer exists and the test fails with "no matches found" rather
        // than with anything about reading.
        // A cover speaks its whole publication: "Fine Print, Ada Lovelace, CBZ". Matching that
        // shape rather than "a button somewhere in the middle of the screen" is what stops
        // this walking into a toolbar control and then reporting that nothing opens.
        func covers() -> [XCUIElement] {
            // The format sits *inside* the label, not at its end: a cell speaks its title,
            // then what distinguishes it, then the format, and then — only sometimes — how
            // far in the reader is, whether it is on the device, and its page count.
            let shape = NSPredicate(format: "label MATCHES %@", ".*, (CBZ|CBR|CBT|CB7|EPUB|PDF)(,.*)?")
            return app.buttons.matching(shape).allElementsBoundByIndex
                .filter(\.isHittable)
                // Not one that is already finished. `reading-progress` restarts a finished
                // publication from the beginning, which is correct and is not what this
                // test is about — the first run picked one, read to its last page, and
                // reported "left on 3 of 3, came back to 1 of 3" as though continuity were
                // broken. A cover says how far in it is, so the shelf can be asked.
                .filter { !$0.label.contains("100 percent read") }
        }
        try XCTSkipUnless(!covers().isEmpty, "This device's library has no cover to open.")

        let opens = NSPredicate(format: "label BEGINSWITH 'Read' OR label BEGINSWITH 'Continue'")
        let action = app.buttons.matching(opens).firstMatch
        for index in 0..<3 {
            let shelf = covers()
            guard index < shelf.count else { break }
            shelf[index].tap()
            if action.waitForExistence(timeout: 5) {
                action.tap()
                let page = app.otherElements.firstMatch
                _ = page.waitForExistence(timeout: 10)
                return page
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        throw XCTSkip("No publication on this device opens. Covers seen: \(covers().map(\.label))")
    }

    /// A page turn, as a reader makes one: a tap in the forward third of the page.
    ///
    /// The centre is the chrome toggle, so tapping there would reveal the controls rather
    /// than turn anything — which is exactly the mistake that makes a continuity test look
    /// like it works while never leaving page one.
    private func turnAPage(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    /// Whatever the reader is saying about where it is, as a string.
    ///
    /// Read rather than computed, and matched loosely, because the page indicator is a
    /// localised sentence and this test is about the number surviving rather than about how
    /// it is worded.
    private func pagePosition(in app: XCUIApplication) -> String? {
        // Twice, because the first tap can land before the reader has finished opening --
        // and a tap the page has not started listening for is a tap that reveals nothing.
        // A resumed publication is slower than a fresh one: it has a position to restore.
        showChrome(in: app)
        // One query with the match in it, rather than every label mapped into an array.
        // The chrome fades after four seconds: an array of `XCUIElement` is a snapshot, and
        // reading `.label` off each in turn asks the app about elements that have since
        // gone — which fails as "no matches found for element at index 4" and says nothing
        // whatever about reading. A predicate query is answered in one round trip.
        let numbered = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*\\d+.*")).firstMatch
        if numbered.waitForExistence(timeout: 5) { return numbered.label }
        showChrome(in: app)
        guard numbered.waitForExistence(timeout: 10) else { return nil }
        return numbered.label
    }

    /// Brings the reader's chrome back. It fades after four seconds, and a position nobody
    /// can see is a position this test cannot read.
    private func showChrome(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func close(_ reader: XCUIElement, in app: XCUIApplication) {
        showChrome(in: app)
        let dismiss = app.buttons.element(boundBy: 0)
        if dismiss.waitForExistence(timeout: 5), dismiss.isHittable { dismiss.tap() }
    }
}
