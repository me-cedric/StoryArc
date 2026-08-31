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
    /// **Three contrast issues remain**, and the audit is the only thing that knows which
    /// elements they are. It ran for the first time on 2026-08-31: until then the target
    /// could not be code-signed at all — `project.yml` gave it no `Info.plist` and did not
    /// ask Xcode to generate one — so the build failed before a single test started, and
    /// this expectation had never once been evaluated.
    ///
    /// The annotation used to name `ScanSummary`'s `textTertiary` on `storyArcGlass` as
    /// the whole of it. That one is fixed: text on glass now takes the material's own
    /// hierarchy rather than a fixed palette colour. Three failures survived it, which is
    /// exactly why the reason is no longer allowed to name a cause — an expectation that
    /// names one defect and silently absorbs three is worse than no expectation at all.
    ///
    /// `XCTExpectFailure` rather than a disabled test, so this starts failing the moment
    /// the last of them is fixed and this annotation is left behind.
    func testHomePassesTheAudit() throws {
        XCTExpectFailure("Contrast issues remain on Home. Read the report below for which.")
        let app = launch()
        try audit(app, named: "Home")
    }

    /// The library shelf, which is a different screen from the one the app opens on.
    ///
    /// It was not audited before, because nothing navigated: the app used to open on the
    /// library and the shell revamp moved Home in front of it, so the one audit this
    /// project had quietly stopped covering the screen it was named after.
    func testLibraryPassesTheAudit() throws {
        // Nine issues on first run, 2026-08-31, printed in full by `audit`. Two kinds:
        //
        // - **Contrast, eight of them**, and seven sit in the bottom 260 pt of the window
        //   — under the floating glass tab bar and the scan summary. Untinted glass takes
        //   its luminance from the cover behind it, so the audit cannot bound the contrast
        //   of anything it overlaps, and text that scrolls under the bar is text the audit
        //   fails. This is the same finding the token gate already has a hole for: no text
        //   role is measured against glass, because glass is not one of the three opaque
        //   surfaces it measures.
        // - **"Dynamic Type font sizes are partially unsupported"** on a coverless card's
        //   title, which is a real and separate defect: that title carries
        //   `minimumScaleFactor`, and shrinking text below the reader's chosen size is
        //   precisely what `design.md` forbids.
        XCTExpectFailure("Contrast under the glass bar, and one minimumScaleFactor. See the report below.")
        let app = launch()
        try XCTUnwrap(destination("Library", in: app)).tap()
        try audit(app, named: "Library")
    }

    /// What is readable with no network. The third destination, and the smallest.
    func testDownloadsPassesTheAudit() throws {
        // Seven issues on first run, 2026-08-31. Five are **"Text clipped"** on shelf
        // captions, each 18 pt tall — a caption given one line's height and asked to draw
        // two. That is a layout defect and not a glass one, and it is the most fixable
        // thing this audit has ever reported. The remaining two are the same
        // under-the-bar contrast as the library.
        XCTExpectFailure("Five clipped captions and two under the glass bar. See the report below.")
        let app = launch()
        try XCTUnwrap(destination("Downloads", in: app)).tap()
        try audit(app, named: "Downloads")
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
    /// Runs the audit and prints what it found before letting it fail.
    ///
    /// `performAccessibilityAudit()` on its own reports "Contrast failed" and nothing else
    /// — no element, no label, no frame — so a known failure stays known and never becomes
    /// fixable. The handler is the documented way to see the issue itself; returning
    /// `false` from it keeps the failure, so this reports *and* still fails.
    ///
    /// The element description is the useful half: it carries the label and the frame,
    /// which together identify the view in a codebase where every screen is built from
    /// small named pieces.
    private func audit(
        _ app: XCUIApplication,
        named screen: String,
        types: XCUIAccessibilityAuditType = .all
    ) throws {
        var found: [String] = []
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element?.debugDescription ?? "no element reported"
            found.append("  • \(issue.compactDescription)\n    \(element)")
            return false
        }
        if !found.isEmpty {
            print("Accessibility audit — \(screen): \(found.count) issue(s)")
            for line in found { print(line) }
        }
    }

    /// One of the shell's three destinations, wherever the platform decided to draw it.
    ///
    /// A tab is a `tabBars` button on a phone and a sidebar row on a wide iPad, because
    /// the shell is `.sidebarAdaptable`. Asking for both rather than one means this test
    /// does not silently stop navigating the day it runs on an iPad.
    private func destination(_ name: String, in app: XCUIApplication) -> XCUIElement? {
        for candidate in [app.tabBars.buttons[name], app.buttons[name], app.staticTexts[name]]
        where candidate.waitForExistence(timeout: 5) && candidate.isHittable {
            return candidate
        }
        return nil
    }

    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }
}
