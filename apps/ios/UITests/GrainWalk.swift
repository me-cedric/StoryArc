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
        let app = sweepLaunch(natural: true)
        try openReflowable(in: app)
        shutter(app, named: "ios-reader-grain-on")
    }

    /// The same page with Natural off: the twin the texture is measured against.
    func testCaptureReaderGrainOff() throws {
        let app = sweepLaunch(natural: false)
        try openReflowable(in: app)
        shutter(app, named: "ios-reader-grain-off")
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
            openReflowable(named: "The Long Field", in: app),
            "This device's shelf never opened a reflowable book, so there is no page to grain."
        )
        // Long enough for the chrome countdown, and for the web view to have laid out: a
        // grain frame taken over a blank page is a picture of the grain over nothing.
        hold(8)
    }

    /// Opens one publication by name and says whether a reflowable page arrived.
    ///
    /// A copy of `SweepEpubReaderTests`' own private helper rather than a call to it: that one
    /// is `private` to its file, and the alternative — the shared search — is the relaunching
    /// walk this file cannot use.
    private func openReflowable(named title: String, in app: XCUIApplication) -> Bool {
        guard (try? showTheShelf(in: app)) != nil else { return false }
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        var cover: XCUIElement?
        for _ in 0..<8 where cover == nil {
            cover = wanted.allElementsBoundByIndex.first(where: \.isHittable)
            if cover == nil { app.swipeUp() }
        }
        guard let cover else { return false }
        cover.tap()
        guard app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 8),
              let action = app.buttons.matching(opensAPublication)
                  .allElementsBoundByIndex.first(where: \.isHittable)
        else { return false }
        action.tap()
        let opened = app.webViews.firstMatch.waitForExistence(timeout: 20)
        if !opened {
            // A skip that photographs nothing is a skip nobody can diagnose. This is the
            // frame that says what the reader actually did.
            shutter(app, named: "ios-reflowable-did-not-open")
        }
        return opened
    }
}
