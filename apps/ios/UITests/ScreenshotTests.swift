import XCTest

/// Photographs a screen, so that `AGENTS.md` section 6's visual proof is repeatable.
///
/// Android has `pnpm capture:android`, which walks to a named screen, sets the text size and
/// the appearance, photographs it, and puts the device back. iOS had `xcrun simctl io booted
/// screenshot`, which photographs whatever happens to be in front of it — so every iOS proof
/// this project has taken involved a person driving the simulator by hand, and the one time
/// that was automated with synthetic clicks the coordinates missed the tab bar and produced
/// a picture of Home labelled *Downloads*.
///
/// A UI test already knows how to reach a screen: `AuditWalk.swift` owns that, and the audit
/// suite has been walking these same destinations for a day. Reusing it means the capture
/// cannot drift away from the walk that the audit and the crash checks use.
///
/// The screenshots come out of the result bundle:
/// ```
/// xcodebuild test -project apps/ios/StoryArc.xcodeproj -scheme StoryArc \
///   -destination 'platform=iOS Simulator,name=StoryArc-iPhone17Pro' \
///   -only-testing:StoryArcUITests/ScreenshotTests -resultBundlePath /tmp/shots.xcresult
/// xcrun xcresulttool export attachments --path /tmp/shots.xcresult --output-path /tmp/shots
/// ```
///
/// `.keepAlways` matters: an attachment on a passing test is deleted by default, and a
/// capture suite whose every test passes would produce nothing at all.
@MainActor
final class ScreenshotTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCaptureDownloads() throws {
        let app = launch()
        try XCTUnwrap(destination("Downloads", in: app)).tap()
        // The shelf, not the tab: tapping a tab is instant and decoding covers is not, and a
        // screenshot taken between the two shows an empty grid on every build alike — which
        // would make a before and an after identical for a reason that has nothing to do
        // with the change.
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "downloads")
    }

    func testCaptureHome() throws {
        let app = launch()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "home")
    }

    func testCaptureLibrary() throws {
        let app = launch()
        try XCTUnwrap(destination("Library", in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "library")
    }

    /// The library at the largest accessibility text size.
    ///
    /// Android's filter chip row ran off the window at `font_scale 2.0` and had to learn to
    /// wrap. The question this answers is whether iOS's equivalent has the same defect, and
    /// it is a fair question because both platforms draw the same three controls — narrow to
    /// what is on this device, choose an order, filter.
    ///
    /// They do not draw them the same way, which is the answer: iOS puts them in a toolbar
    /// as icons, and an icon does not grow with the reader's text. The picture is what says
    /// so, because a claim that a row cannot overflow is worth exactly as much as the
    /// largest text size somebody actually pointed at it.
    func testCaptureLibraryAtLargestText() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try XCTUnwrap(destination("Library", in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "library-ax5")
    }

    /// The theme sheet and its six presets, which `reader-theming-and-page-transitions`
    /// task 7.4 asks for and which has been recorded as impossible on this platform.
    ///
    /// That task said "iOS cannot be captured: the simulator accepts no injected input, so the
    /// reader cannot be reached to open the sheet", and `apps/ios/README.md` records the three
    /// approaches that were tried. Input was never the obstacle: a UI test injects through
    /// XCUITest rather than through the Simulator's window.
    ///
    /// What the blocker was narrowed to next — "the EPUB reader does not reach a state with
    /// its own controls" — does not follow either, because that run never established which
    /// reader it was in. It asked for an EPUB, and a **fixed-layout** EPUB satisfies that and
    /// is not opened in the reflowable reader at all. Whether the reflowable reader has a
    /// problem of its own is a thing no run has measured yet.
    ///
    /// The sheet lives in the **EPUB** reader, not the comic reader, because a reading theme
    /// applies to reflowable text. Its control is labelled *Reading* — `theme.title` in
    /// `EpubReaderFeature`. A fixed-layout EPUB cannot be used for this, and the reason is
    /// one screen earlier than it looks: `Publication.isReflowable` is false for one, so the
    /// app opens it in the comic reader, where the reading themes have no control of their
    /// own. Asking the shelf for "an EPUB" is therefore not enough — see
    /// ``openTheEpubReader(in:)``, which is what made this capture possible.
    ///
    /// All six presets are in one shot deliberately, following the Android captures: the grid
    /// draws each preset in its own colours *and* its own typeface, and that is the thing worth
    /// proving. Six separate screenshots would prove less.
    func testCaptureThemeSheet() throws {
        try captureThemeSheet(contentSize: nil, named: "theme-sheet")
    }

    /// The same sheet at the largest accessibility text size, which is the half task 7.4 names
    /// separately — a specimen is a picture of a typeface in a card of fixed height, and that
    /// is exactly the shape that clips when the reader's type grows.
    func testCaptureThemeSheetAtLargestText() throws {
        try captureThemeSheet(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            named: "theme-sheet-largest"
        )
    }

    private func captureThemeSheet(contentSize: String?, named name: String) throws {
        let app = launch(contentSize: contentSize)
        // Waits for the control itself, not for `otherElements.firstMatch` — that exists on
        // every screen and returns instantly, so the first version of this walked on while
        // the publication page was still up, tapped its middle, and reported no theme sheet
        // on a screen that never had one. And it opens EPUBs until one of them lands in the
        // reflowable reader **with a page in it**, because a cover cannot say which of the
        // two readers it opens and the theme control is drawn over the loading spinner as
        // readily as over a book. A version that stopped at the first EPUB skipped every run
        // for a day. When no EPUB on the device gets there it still skips, and names every
        // one it tried and how far each got.
        try openTheEpubReader(in: app)
        let reading = app.buttons["Reading"]
        reading.tap()
        // The sheet is a presentation; it animates up over the page.
        _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Original")).firstMatch
            .waitForExistence(timeout: 5)
        attach(app.screenshot(), named: name)
    }

    private func attach(_ shot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
