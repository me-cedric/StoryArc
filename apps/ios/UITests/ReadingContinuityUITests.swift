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
        executionTimeAllowance = 280
    }

    /// Reads a few pages, closes the publication, relaunches, and reopens it.
    ///
    /// Relaunching rather than reopening from the same process is the whole point: an
    /// in-memory position survives a dismissal for free, and the thing worth proving is
    /// that it reached the store and came back out of it.
    func testAPublicationResumesWhereItWasLeft() throws {
        // **Every preference stated, not inherited.** This launched bare, and a bare launch
        // takes the shelf state whichever walk ran before it left behind — the layout, the
        // grouping, the availability axis and the query all persist, which is exactly what
        // `sweepLaunch(_:)`'s own note says they do. Measured on a runner on 2026-09-12: the
        // shelf held one cover, an audiobook marked *100% read*, and this walk
        // reported "This library has nothing to read" about a device holding two
        // publications. `sweepLaunch()` passes every key, so the shelf is at rest.
        //
        // The relaunch below keeps them: `launch()` re-applies the arguments already set on
        // this instance, so the second launch starts in the same state as the first.
        let app = sweepLaunch()

        // Remembered, so the relaunch reopens the *same* publication.
        // The shelf is named in the failure, because "nothing to read" reads like a missing
        // fixture and has twice been a cover whose spoken label this walk did not recognise.
        let opened = try XCTUnwrap(
            readablePublication(in: app),
            "This library has nothing to read. On the shelf: "
                + app.buttons.allElementsBoundByIndex.prefix(30).map(\.label).joined(separator: " | ")
        )
        let action = try reopen(opened, in: app)
        let actionLabel = action.label
        action.tap()
        let reader = app.otherElements.firstMatch
        _ = reader.waitForExistence(timeout: 10)
        // One turn. Enough that resuming on the first page would fail — which is the whole
        // property — and few enough that a three-page fixture does not reach its last page
        // and get restarted by the finished rule instead.
        let initial = pagePosition(in: app)
        // Forward from the first page. From any later one, back: a book resumed on its second
        // page of three would reach the last by turning on, and the finished rule restarts it.
        let page = initial?.range(of: #"\d+"#, options: .regularExpression).map { initial?[$0] }
        let onFirstPage = page.flatMap { $0 } == "1"
        turnAPage(in: app, forward: onFirstPage)
        let left = try XCTUnwrap(pagePosition(in: app), "The reader shows no position to read.")
        close(reader, in: app)

        app.terminate()
        app.launch()
        try reopen(opened, in: app).tap()
        _ = app.otherElements.firstMatch.waitForExistence(timeout: 10)
        let resumed = try XCTUnwrap(pagePosition(in: app), "The reader shows no position after relaunching.")

        XCTAssertEqual(
            resumed, left,
            """
            Opened \(opened) with "\(actionLabel)" at \(initial ?? "nothing").
            Left on \(left) and came back to \(resumed).
            A position that does not survive a relaunch is the one thing this app promises never to lose.
            """
        )
    }

    // MARK: - Private

    /// The same publication again, found by its title.
    ///
    /// Not by its whole label: a cover states how far in it is, so reading a page rewrites the
    /// label, and a lookup by the old one found nothing and skipped (2026-10-09).
    private func reopen(_ label: String, in app: XCUIApplication) throws -> XCUIElement {
        let title = label.components(separatedBy: ", ")[0]
        try showTheShelf(in: app)
        waitForTheShelfToSettle(in: app)
        let cover = try XCTUnwrap(tappableCover(titled: title + ", ", in: app), "The shelf shows no \(title).")
        cover.tap()
        return try XCTUnwrap(hittableOpenAction(in: app), "The page for \(title) offered no way to open it.")
    }

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
            format: "label MATCHES %@", ".*[,·] (CBZ|CBR|CBT|CB7|PDF)\\b.*"
        )
        let readable = app.buttons.matching(shape)
        guard readable.firstMatch.waitForExistence(timeout: 15) else { return nil }
        // **On this device, not only readable in principle.** A simulator that capture walks
        // have used also holds rows from the mock servers, spoken as "Needs its library to be
        // reachable" when no mock is running. On 2026-09-29 this walk picked one on such a
        // simulator, and the reader had no page to open. A runner holds no such row.
        return readable.allElementsBoundByIndex
            .first {
                $0.isHittable && !$0.label.contains("100% read")
                    && !$0.label.contains("Needs its library to be reachable")
            }?
            .label
    }

    /// A page turn, as a reader makes one: a tap in the forward third of the page.
    ///
    /// The centre is the chrome toggle, so tapping there would reveal the controls rather
    /// than turn anything — which is exactly the mistake that makes a continuity test look
    /// like it works while never leaving page one.
    private func turnAPage(in app: XCUIApplication, forward: Bool = true) {
        app.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.9 : 0.1, dy: 0.5)).tap()
    }

    /// Whatever the reader is saying about where it is, as a string.
    ///
    /// Read rather than computed, and matched loosely, because the page indicator is a
    /// localised sentence and this test is about the number surviving rather than about how
    /// it is worded.
    private func pagePosition(in app: XCUIApplication) -> String? {
        // **Read off the page, not off the chrome.** Since `quiet-reader` the chrome over a
        // comic is two icon buttons and states no position; the page itself carries it, as
        // its spoken label ("Page 2 of 3", `reader.pageLabel`). Looking for a number in the
        // chrome's static text found nothing, which is why this walk failed on CI from
        // 2026-09-12 with "The reader shows no position to read". Two numbers in one label is
        // the page's shape and nothing else on the reader's screen has it.
        let page = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", ".*\\d+\\D+\\d+.*"))
            .firstMatch
        guard page.waitForExistence(timeout: 10) else { return nil }
        // **Read again until it holds still.** A reader draws page one while its archive opens,
        // and moves to the recorded page when the record arrives. The first read of a reopened
        // publication is the page it started on, not the one it resumed to (2026-10-09).
        var seen = page.label
        for _ in 0..<6 {
            hold(1)
            let now = page.exists ? page.label : seen
            if now == seen { return now }
            seen = now
        }
        return seen
    }

    /// By its name, and with no other button in its place: a tap on another button turned the
    /// reader back a page before it closed (2026-10-09).
    ///
    /// The centre tap only when the chrome is down. The chrome is often still up from the turn,
    /// and a centre tap then hid the Close button it was meant to show.
    private func close(_ reader: XCUIElement, in app: XCUIApplication) {
        let close = app.buttons["Close"].firstMatch
        if !(close.exists && close.isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(close.waitForExistence(timeout: 5) && close.isHittable, "The reader shows no Close button.")
        close.tap()
        hold(1)
    }
}
