import XCTest

/// Apple's own accessibility audit, run over the screens a reader can reach.
///
/// The iOS counterpart of `pnpm a11y:android`, and it exists for the same reason: three
/// accessibility defects reached a commit and none was visible in a screenshot. A comic
/// page announced its file name, a colour swatch announced a hex code, and a settings
/// row's tap target depended on how long its label happened to be.
///
/// `performAccessibilityAudit` is the platform's check rather than ours. It applies the
/// rules Xcode's Accessibility Inspector applies — contrast, text clipped at large sizes,
/// hit-region size, missing element description, conflicting traits — so this test cannot
/// drift from what iOS considers correct. Writing our own would mean maintaining a second
/// opinion about Apple's guidelines.
///
/// A UI test rather than a unit test because the audit needs a running app. That is the
/// only reason this target exists.
@MainActor
final class AccessibilityAuditTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        // Every issue, not just the first. One screen usually has more than one, and
        // stopping at the first turns a full report into a single line.
        continueAfterFailure = true
    }

    /// Audits the library, which is the first thing anyone sees.
    ///
    /// Expected to fail on one known defect, which this audit found the first time it ran:
    /// `ScanSummary` draws `textTertiary` on `storyArcGlass`, and what sits behind glass is
    /// cover art, so the contrast is not a number anyone can bound. The comic reader chrome
    /// had the same defect and was fixed by putting a scrim behind the text. Fixing it here
    /// means auditing every glass surface that carries text, which is its own piece of
    /// work.
    ///
    /// `XCTExpectFailure` rather than a disabled test, so this starts failing the moment
    /// the defect is fixed and this annotation is left behind.
    func testLibraryPassesTheAudit() throws {
        XCTExpectFailure("Known: textTertiary on storyArcGlass in ScanSummary")
        let app = launch()
        try app.performAccessibilityAudit()
    }

    // Settings is not audited here yet. The audit reports five issues across the list and
    // its four groups — one contrast failure, one contrast "nearly passed", and two fonts
    // that do not follow Dynamic Type — and none is traced to an element, because
    // `xcodebuild` prints the audit's verdict without the element description. Reading that
    // needs the Xcode result bundle. The findings are written down in
    // `settings-and-about-screens` task 6.3 so they are not lost with this comment.

    // MARK: - Private

    /// Launches the app, optionally at a chosen text size.
    ///
    /// The size arrives as a launch argument rather than by driving the Settings app: it is
    /// the documented way to force a content-size category in a UI test, and it applies
    /// before the first frame, so nothing is measured at the default size first.
    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }
}
