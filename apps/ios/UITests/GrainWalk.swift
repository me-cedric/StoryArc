import XCTest

/// The procedural paper grain, photographed so it can be **judged**.
///
/// `reader-theming-and-page-transitions` §0.5 asked for a prototype on both platforms and a
/// judgement of whether it reads as paper; §5.4 built the shader on both and wired it to the
/// page, and recorded that "0.5's own question is a *judgement*, and that still needs a
/// screen". No iOS frame of it existed. These are those frames.
///
/// The grain is procedural noise rather than a bundled tile — cheaper, resolution-independent,
/// no bytes — one hash, two octaves at 2.17× so the two lattices never line up, and a warm/dark
/// tint pair rather than symmetric grey, because grey speckle reads as sensor noise, which is
/// the one thing this must not look like.
///
/// **A pair, not a single frame.** Grain at a plausible strength is nearly invisible in
/// isolation and obvious in comparison, so every capture here has a Natural-off twin taken
/// through the same walk. The difference between the two *is* the texture, and it can be
/// measured off the pair rather than argued about.
@MainActor
final class GrainWalkTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The reflowable page with the grain on, which is the surface §5.4 draws it over.
    func testCaptureReaderGrainOn() throws {
        let app = sweepLaunch(natural: true, freshShelfSettings: true)
        try openReflowable(in: app)
        shutter(app, named: "ios-reader-grain-on")
    }

    /// The same page with Natural off: the twin the texture is measured against.
    func testCaptureReaderGrainOff() throws {
        let app = sweepLaunch(natural: false, freshShelfSettings: true)
        try openReflowable(in: app)
        shutter(app, named: "ios-reader-grain-off")
    }

    /// The dark pair, task 0.5: grain over a dark page, which is a different perceptual problem
    /// from grain over cream, because the same modulation is a larger part of the range there.
    /// The page is the Quiet preset, chosen through the theme sheet, so the pair differs in
    /// Natural alone.
    func testCaptureReaderGrainOnQuiet() throws {
        let app = sweepLaunch(natural: true, freshShelfSettings: true)
        try openReflowable(in: app)
        try chooseQuiet(in: app)
        shutter(app, named: "ios-reader-grain-on-quiet")
    }

    func testCaptureReaderGrainOffQuiet() throws {
        let app = sweepLaunch(natural: false, freshShelfSettings: true)
        try openReflowable(in: app)
        try chooseQuiet(in: app)
        shutter(app, named: "ios-reader-grain-off-quiet")
    }

    /// The refusal, task 0.5 and 7.6: Natural on and **Reduce Transparency on**. The grain must
    /// vanish, so this frame measured against `ios-reader-grain-off` changes nothing.
    func testCaptureReaderGrainRefusedByReduceTransparency() throws {
        try setDisplaySwitch("Reduce Transparency", on: true)
        addTeardownBlock { @MainActor in try? self.setDisplaySwitch("Reduce Transparency", on: false) }
        let app = sweepLaunch(natural: true, freshShelfSettings: true)
        try openReflowable(in: app)
        shutter(app, named: "ios-reader-grain-refused")
    }

    /// The same refusal over the dark page, against `ios-reader-grain-off-quiet`.
    func testCaptureReaderGrainRefusedByReduceTransparencyOnQuiet() throws {
        try setDisplaySwitch("Reduce Transparency", on: true)
        addTeardownBlock { @MainActor in try? self.setDisplaySwitch("Reduce Transparency", on: false) }
        let app = sweepLaunch(natural: true, freshShelfSettings: true)
        try openReflowable(in: app)
        try chooseQuiet(in: app)
        shutter(app, named: "ios-reader-grain-refused-quiet")
    }

    private func chooseQuiet(in app: XCUIApplication) throws {
        try XCTUnwrap(revealed("Menu", in: app), "The reader revealed no menu to open.").tap()
        for _ in 0..<5 where hittableRow("Reading themes", in: app, timeout: 1) == nil {
            app.swipeUp()
            hold(0.7)
        }
        try XCTUnwrap(hittableRow("Reading themes", in: app), "The menu offers no reading-themes row.").tap()
        let quiet = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Quiet")).firstMatch
        XCTAssertTrue(quiet.waitForExistence(timeout: 8), "The theme sheet offers no Quiet preset.")
        quiet.tap()
        hold(1)
        for _ in 0..<3 {
            guard let done = hittableRow("Done", in: app, timeout: 3) else { break }
            done.tap()
            hold(1)
        }
        XCTAssertTrue(app.buttons["Done"].waitForNonExistence(timeout: 8), "A sheet is still over the page.")
        hold(8)
    }

    /// Opens a reflowable book and lets the chrome time out, so the frame is page only.
    ///
    /// The grain draws between the page and the chrome — over the words, under the app bars —
    /// so a frame with the bars up is a frame of the bars.
    ///
    /// **This walk is why the doubled shelf was found**, and the story is worth keeping. It
    /// skipped, and so did `SweepEpubReaderTests`, and a skip photographs nothing — so the
    /// first guess was a server copy shadowing the local file. It was not: the library was
    /// restoring a cached row whose path had died with the app container and then adding the
    /// one the scan found, so every publication was on the shelf twice and the fileless twin
    /// sorted first. `LibraryModel.restoreCachedLibrary` drops those rows now. The lesson for
    /// this file is that a walk which skips should say *what it saw*; the diagnostic that
    /// found this photographed each step and was deleted once it had.
    ///
    /// **By name, and `openTheEpubReader(in:)` is not usable here.** That walk relaunches the
    /// app between attempts, and a relaunch drops the launch arguments — including
    /// `-storyarc.appearance.natural`, which is the entire variable under test. The first run
    /// of this file skipped for that reason, having found no reflowable book before its
    /// attempts ran out, and had it succeeded it would have photographed a *default* theme
    /// under a filename saying Natural.
    private func openReflowable(in app: XCUIApplication) throws {
        try XCTSkipUnless(
            openReflowableBook(named: "The Long Field", in: app),
            "This device's shelf never opened a reflowable book, so there is no page to grain."
        )
        // Long enough for the chrome countdown, and for the web view to have laid out: a
        // grain frame taken over a blank page is a picture of the grain over nothing.
        hold(8)
    }

}
