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

        // Remembered, so the relaunch reopens the *same* publication.
        // The shelf is named in the failure, because "nothing to read" reads like a missing
        // fixture and has twice been a cover whose spoken label this walk did not recognise.
        let opened = try XCTUnwrap(
            readablePublication(in: app),
            "This library has nothing to read. On the shelf: "
                + app.buttons.allElementsBoundByIndex.prefix(30).map(\.label).joined(separator: " | ")
        )
        let action = try openFirstPublication(in: app, named: opened)
        action.tap()
        let reader = app.otherElements.firstMatch
        _ = reader.waitForExistence(timeout: 10)
        // One turn. Enough that resuming on the first page would fail — which is the whole
        // property — and few enough that a three-page fixture does not reach its last page
        // and get restarted by the finished rule instead.
        turnAPage(in: app)
        let left = try XCTUnwrap(pagePosition(in: app), "The reader shows no position to read.")
        close(reader, in: app)

        app.terminate()
        app.launch()
        try openFirstPublication(in: app, named: opened).tap()
        _ = app.otherElements.firstMatch.waitForExistence(timeout: 10)
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

    /// The label of the first publication on the shelf that can be read from.
    ///
    /// **It waits for the shelf to draw, and that is the whole of what was wrong here.** The
    /// library is scanned from disk when the shell appears, so the tab is on screen a good
    /// while before a cover is. This asked the moment it had tapped the tab, got an empty
    /// array on a device holding a hundred and forty publications, and reported "This library
    /// has nothing to read" — which is the one sentence that reads like a missing fixture
    /// rather than a missing wait. `AuditWalk.showTheShelf(in:)` waits for the same reason.
    private func readablePublication(in app: XCUIApplication) -> String? {
        guard let library = destination("Library", in: app) else { return nil }
        library.tap()
        // **Either separator, and that is the defect this line carried.** A cover's spoken
        // label states the format after the caption, and the caption joins its own parts with
        // a middle dot — measured on 2026-09-11 as `Bright Panels, Ada Lovelace · EPUB`. The
        // pattern asked for a comma before the format and so matched nothing on a shelf of a
        // hundred and forty publications, which this walk then reported as an empty library.
        // What is asserted is unchanged: a cover of a format a reader can read is on the shelf.
        //
        // **`EPUB` stays in the set, and the reason is worth leaving here.** This walk reads
        // the reader's own position indicator, and an EPUB has no page to state — so the ideal
        // set is the paged formats alone. Measured on 2026-09-11, the Library shelf under a
        // plain launch offered six covers and not one comic or PDF among them, while
        // `Library/Caches/library.json` held fourteen CBZ and a PDF. Narrowing the set there
        // only moves the failure back to this line. Narrow it once the shelf draws what the
        // library holds.
        let shape = NSPredicate(
            format: "label MATCHES %@", ".*[,·] (CBZ|CBR|CBT|CB7|EPUB|PDF)\\b.*"
        )
        let readable = app.buttons.matching(shape)
        guard readable.firstMatch.waitForExistence(timeout: 15) else { return nil }
        return readable.allElementsBoundByIndex
            .first { $0.isHittable && !$0.label.contains("100 percent read") }?
            .label
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
