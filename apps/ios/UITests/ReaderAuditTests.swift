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
    /// this suite went no further than the three destinations. The chrome auto-hides after
    /// four seconds, so this taps the centre of the page to bring it back before measuring
    /// — an audit of a page with no chrome on it measures the artwork and nothing else.
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
        // Naming it rather than suppressing it, because the shape of the finding is right
        // even though there is nothing to do about it here — and because the same check on
        // the **EPUB** reader would be a real finding, since there the words are real text
        // in a WebView. That reader is not audited yet; when it is, this comment is the
        // reason its result must not be read the same way.
        let app = launch()
        let action = try openFirstPublication(in: app)
        action.tap()

        // The chrome fades after four seconds. Bring it back, or this measures a page of
        // artwork with no controls on it and reports that everything is well.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

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
        // **It proves it arrived, twice over, and the second proof is why this test ran for
        // a day without measuring the reader.**
        //
        // The first version tapped the action element `openFirstPublication` returned and
        // audited whatever was on screen. That element is not always hittable — the
        // publication page has duplicate entries in its hierarchy and `firstMatch` can bind
        // to one that cannot be tapped — so it reported "zero findings on the EPUB reader"
        // while sitting on the publication page.
        //
        // The version after it tapped a hittable action and then waited for the theme
        // control, and skipped for twenty seconds' worth of waiting every time. That was
        // honest and it was reported as "the EPUB reader does not reach a state with its own
        // controls on this simulator". It does. What it asked the shelf for was an *EPUB*,
        // and two of this corpus's five are pre-paginated and sort first — so it opened the
        // **comic** reader, which has no theme control and never will.
        //
        // `openTheEpubReader` is the fix: it keeps opening EPUBs until the reader it lands
        // in is the one with the control on it.
        let app = launch()
        try openTheEpubReader(in: app)

        try reportOnly(app, named: "EPUB reader")
    }

}
