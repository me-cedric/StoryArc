import XCTest

/// The two readers, audited separately, because they are two different screens.
///
/// Split out of `AccessibilityAuditTests` when it passed the 400-line cap. The division is
/// the one the audits already made: the comic reader shows photographs of printed pages and
/// the EPUB reader shows real text in a WebView, so the same finding means opposite things on
/// the two and they cannot share a verdict.
@MainActor
final class ReaderAuditTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The reader, which is where the whole app is going and which nothing has ever audited.
    ///
    /// It is the screen a reader spends their time in and the one the other two checks
    /// cannot reach: `pnpm a11y:android` reads whatever is on the emulator's screen, and
    /// this suite went no further than the three destinations.
    ///
    /// **The chrome has to be on screen, and getting it there was backwards.** This used to
    /// tap the centre of the page immediately after opening, under a comment about bringing
    /// the chrome back after its four-second fade. `ReaderView`'s `wantsChrome` starts `true`
    /// — `comic-reader` wants the way out discoverable — and a centre tap *toggles* it
    /// (`ReaderTurning.handleTap`), so the tap removed the chrome this test exists to measure
    /// and every run so far audited a bare page. It is the same mistake, inverted, as the one
    /// this branch was opened for.
    ///
    /// So the chrome is looked for rather than summoned: *Close* is `reader.close` in
    /// `ReaderChromeControls`, and a tap happens only if four seconds have already passed and
    /// it has gone. What no wait can do is stop the timer — if the audit itself starts more
    /// than four seconds after the chrome appeared, it measures the page again. That is worth
    /// knowing when a run's finding count changes and nothing in the app did.
    ///
    /// Skipped rather than failed when the library has nothing openable in it. A device
    /// whose sources have all gone away is a real state, and a suite that reports a defect
    /// because its fixtures are missing is a suite nobody believes twice.
    func testReaderPassesTheAudit() throws {
        // **Two "Potentially inaccessible text" findings, and they are what a comic is.**
        // That check looks for lettering inside an image with no accessibility element
        // answering for it, and reports the image rather than an element — which is why
        // both arrive as "no element reported". A scanned comic page *is* lettered artwork:
        // the words are pixels in a photograph of a printed page, and the app has no text
        // to expose because no text was ever delivered to it.
        //
        // That count was recorded from a run whose centre tap had taken the chrome away, so
        // it is a count for the page alone. With the chrome up there is more on screen to
        // audit and the number can differ without anything having regressed.
        //
        // Naming it rather than suppressing it, because the shape of the finding is right
        // even though there is nothing to do about it here — and because the same check on
        // the **EPUB** reader would be a real finding, since there the words are real text
        // in a WebView. That reader is not audited yet; when it is, this comment is the
        // reason its result must not be read the same way.
        let app = launch()
        let action = try openFirstPublication(in: app)
        action.tap()

        // Already up, on a reader that has just opened. Only a chrome that has timed out
        // needs the tap, and a tap on one that has not takes it away.
        let close = app.buttons["Close"]
        if !close.waitForExistence(timeout: 10) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = close.waitForExistence(timeout: 5)
        }

        try reportOnly(app, named: "Reader")
    }

    /// The reflowable EPUB reader, which this suite has never looked at.
    ///
    /// `testReaderPassesTheAudit` above ends by saying so: its two "Potentially inaccessible
    /// text" findings are what a scanned comic *is* — lettering inside a photograph, with no
    /// text ever delivered to the app — and "the same check on the **EPUB** reader would be a
    /// real finding, since there the words are real text in a WebView." So the two readers
    /// cannot share a verdict, and this is the second one.
    ///
    /// It also closes half of an asymmetry `STATUS.md` calls not deliberate: Android's crash
    /// walk reaches sixteen screens and iOS's audit reached thirteen, and the EPUB reader was
    /// one of the three missing. Android's own scanner reports that screen as
    /// `EPUB reader: UNNAMED WebView at [0,371][1080,2028]`, so there is a specific thing to
    /// look for here rather than a hope that nothing turns up.
    ///
    /// Reported rather than failed, like the comic reader and for the same reason: what is on
    /// this screen is whichever EPUB the device happens to hold, and a suite that fails
    /// because of a fixture is a suite nobody believes twice. The walk is what is asserted —
    /// reaching a reflowable book at all — and `XCTSkip` covers a device with no EPUB on it.
    func testEpubReaderPassesTheAudit() throws {
        // **It proves it arrived, and it has been wrong about that twice.**
        //
        // The first version tapped the action element `openFirstPublication` returned and
        // audited whatever was on screen. That element is not always hittable — the
        // publication page has duplicate entries in its hierarchy and `firstMatch` can bind
        // to one that cannot be tapped — so it reported "zero findings on the EPUB reader"
        // while sitting on the publication page.
        //
        // The second tapped a hittable action, waited twenty seconds for the theme control,
        // and skipped. That skip was honest and the conclusion drawn from it was not: it was
        // written down as "the EPUB reader does not reach a state with its own controls on
        // this simulator". Nothing in that run identified the reader it was in. What it
        // asked the shelf for was an *EPUB*, and a cover says its format and nothing about
        // its layout — so a **fixed-layout** one satisfies it, and that one is not opened in
        // the reflowable reader at all. Two of the corpus's five EPUBs are pre-paginated and
        // both sort ahead of the other three by title, which is enough to explain the skip
        // without a defect in either reader; it is not proof of which cover was reached,
        // because the shelf's sort is persisted and these tests reset no app state.
        //
        // So what the reflowable reader does on a simulator is still unmeasured. This is the
        // walk that can find out: it opens EPUBs until one of them lands in that reader with
        // a page in it, and names everything it tried when none of them does.
        let app = launch()
        try openTheEpubReader(in: app)

        try reportOnly(app, named: "EPUB reader")
    }

}
