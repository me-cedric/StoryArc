import XCTest

// How a UI test walks this app, shared by every suite that does.
//
// It was written twice — once in the audit and once in the continuity test — and the two
// copies had already drifted: one matched the reader's action with `label IN {'Read',
// 'Continue'}` and the real label is *Continue reading*, so that copy found the action only
// on publications nobody had opened, and passed by luck of which cover it reached first.
// Walking the app is one problem with one answer.

@MainActor
extension XCTestCase {

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
    func audit(
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

    /// Audits a screen and prints what it found, **without failing**.
    ///
    /// **Which screens get this and which get `audit` is a distinction, not a
    /// convenience.** The three destinations are the app's own chrome — the same shelf, the
    /// same bar, the same notices whatever a device holds — so a finding there belongs to
    /// the app and is worth failing on. The publication page, the reader and the
    /// pseudo-locale walk all measure whichever publication the walk happened to open, and
    /// that changed the moment the walk learned to skip finished publications: three tests
    /// broke at once, one by *gaining* a contrast finding and two by *losing* the findings
    /// their expectations named — which fails just as loudly.
    ///
    /// An expectation that names a finding belonging to a fixture is a test about the
    /// fixture. These report instead, and the walk itself is what they assert.
    ///
    /// Eight screens in one test, and `XCTExpectFailure` covers a whole test — so an
    /// expectation broad enough to absorb the contrast findings on all eight is broad
    /// enough to absorb a navigation failure too, silently. It did, on the first run: seven
    /// `XCTFail`s saying "Settings has no row called …" were swallowed whole and the test
    /// reported success. That is the same failure mode this file warns about elsewhere, and
    /// it is worse here because the thing being hidden was the walk itself.
    ///
    /// So the audit reports and the walk asserts. The findings are printed for a reader of
    /// the log; the only thing that can fail this test is failing to reach a screen — which
    /// is what a crash walk is for, and what `pnpm smoke:android` does on the other
    /// platform. When the contrast findings under the glass bar are settled, this can
    /// become `audit` and gain an expectation of its own.
    func reportOnly(_ app: XCUIApplication, named screen: String) throws {
        var found: [String] = []
        try app.performAccessibilityAudit { issue in
            let element = issue.element?.debugDescription ?? "no element reported"
            found.append("  • \(issue.compactDescription)\n    \(element)")
            return true
        }
        if !found.isEmpty {
            print("Accessibility audit — \(screen): \(found.count) issue(s), reported not failed")
            for line in found { print(line) }
        }
    }

    /// A named control, whatever kind of element the platform made of it.
    ///
    /// A settings row is a `NavigationLink` inside a `List`, which surfaces as a cell or a
    /// static text rather than a button — asking only for a button found none of the seven.
    func control(_ name: String, in app: XCUIApplication) -> XCUIElement? {
        for candidate in [app.buttons[name], app.cells[name], app.staticTexts[name]]
        where candidate.waitForExistence(timeout: 5) && candidate.isHittable {
            return candidate
        }
        return nil
    }

    /// Opens the first publication on the shelf and returns the page's primary action.
    ///
    /// **It proves it arrived, and that is the whole point of it.** The first version of
    /// this walked to the library, tapped what it took to be a cover, and audited whatever
    /// was on screen. When the cover tap did not land, the audit measured *Home* and
    /// reported it under the heading "Publication page" — three findings that belonged to
    /// another screen, filed against one nobody had looked at. A check that can silently
    /// measure the wrong screen is worse than no check: its green is worth nothing and its
    /// red sends you to the wrong file.
    ///
    /// So the page has to identify itself, and what identifies it is the one element only
    /// it has: a primary action reading *Read* or *Continue*. Nothing is audited until that
    /// is on screen.
    ///
    /// Skipped rather than failed when the library holds nothing openable. A device whose
    /// sources have all gone away is a real state, and a suite that reports a defect
    /// because its fixtures are missing is a suite nobody believes twice.
    ///
    /// Covers are chosen by position rather than by name, so this does not depend on which
    /// fixtures a device happens to hold. A cell combines its children, so a cover is a
    /// button carrying the publication's whole spoken label.
    /// **Never one that is already finished.** `reading-progress` restarts a finished
    /// publication from the beginning, deliberately — and a walk that picks one and then
    /// checks where it resumed reports "left on 3 of 3, came back to 1 of 3" as though
    /// continuity were broken. A cover says how far in it is, so the shelf can be asked.
    /// This filter was written once, lost in a refactor, and caught again within the hour
    /// by the test it exists for.
    ///
    /// `named` reopens a particular publication. "The first cover" is not a stable identity
    /// across two launches of a shelf that can reorder between them.
    ///
    /// `ofFormat` picks one the app will open with a particular reader, which is what lets a
    /// caller audit the **EPUB** reader rather than whichever reader the first cover happens
    /// to reach. A cover's spoken label ends with its format, so the shelf can be asked. It
    /// matches the label rather than the fixture's name for the same reason `named` exists:
    /// which fixtures a device holds is not this file's business.
    @discardableResult
    func openFirstPublication(
        in app: XCUIApplication,
        named wanted: String? = nil,
        ofFormat format: String? = nil
    ) throws -> XCUIElement {
        try XCTUnwrap(destination("Library", in: app)).tap()

        let shelf = app.buttons.element(boundBy: 0)
        try XCTSkipUnless(shelf.waitForExistence(timeout: 10), "The library never drew a shelf.")

        // Below the toolbar and above the tab bar: everything between is content.
        let covers = app.buttons.allElementsBoundByIndex
            .filter { $0.isHittable && $0.frame.minY > 150 && $0.frame.maxY < app.frame.height - 100 }
            .filter { !$0.label.contains("100 percent read") }
            .filter { wanted == nil || $0.label == wanted }
            .filter { cover in format.map { cover.label.contains(", \($0)") } ?? true }
        try XCTSkipUnless(
            !covers.isEmpty,
            format.map { "This device's library holds no \($0) to open." }
                ?? "This device's library has no cover to open."
        )

        let opens = NSPredicate(format: "label BEGINSWITH 'Read' OR label BEGINSWITH 'Continue'")
        let action = app.buttons.matching(opens).firstMatch
        for cover in covers.prefix(3) {
            cover.tap()
            if action.waitForExistence(timeout: 5) { return action }
            // Not a cover, or one that cannot be opened. Go back and try the next.
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        throw XCTSkip("No publication on this device opens a page with an action on it.")
    }

    /// One of the shell's three destinations, wherever the platform decided to draw it.
    ///
    /// A tab is a `tabBars` button on a phone and a sidebar row on a wide iPad, because
    /// the shell is `.sidebarAdaptable`. Asking for both rather than one means this test
    /// does not silently stop navigating the day it runs on an iPad.
    func destination(_ name: String, in app: XCUIApplication) -> XCUIElement? {
        for candidate in [app.tabBars.buttons[name], app.buttons[name], app.staticTexts[name]]
        where candidate.waitForExistence(timeout: 5) && candidate.isHittable {
            return candidate
        }
        return nil
    }

    /// Launches the app, optionally at a chosen text size.
    ///
    /// The size arrives as a launch argument rather than by driving the Settings app: it is
    /// the documented way to force a content-size category in a UI test, and it applies
    /// before the first frame, so nothing is measured at the default size first.
    func launch(contentSize: String? = nil, language: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        if let language {
            app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
        }
        app.launch()
        return app
    }
}
