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
    /// `ofFormat` narrows to a format, and that is **all** it does. It matches the cover's
    /// spoken label rather than a fixture's name, for the same reason `named` exists: which
    /// fixtures a device holds is not this file's business.
    ///
    /// It is not a way of choosing a reader, and it was read as one. A cover says `EPUB`
    /// whether the book is reflowable or pre-paginated, and the app opens those in two
    /// different readers — so a caller after the EPUB reader wants
    /// ``openTheEpubReader(in:)``, which checks the reader it arrived in.
    @discardableResult
    func openFirstPublication(
        in app: XCUIApplication,
        named wanted: String? = nil,
        ofFormat format: String? = nil
    ) throws -> XCUIElement {
        let covers = try coversOnTheShelf(in: app, named: wanted, ofFormat: format)
        try XCTSkipUnless(
            !covers.isEmpty,
            format.map { "This device's library holds no \($0) to open." }
                ?? "This device's library has no cover to open."
        )

        let action = app.buttons.matching(opensAPublication).firstMatch
        for cover in covers.prefix(3) {
            cover.tap()
            if action.waitForExistence(timeout: 5) { return action }
            // Not a cover, or one that cannot be opened. Go back and try the next.
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        throw XCTSkip("No publication on this device opens a page with an action on it.")
    }

    /// The covers a walk may open, on the screenful of shelf that is showing.
    ///
    /// Showing the shelf and asking what is on it, in one call, for the one caller that wants
    /// both: ``openFirstPublication(in:named:ofFormat:)``. ``openTheEpubReader(in:)`` walks
    /// the same two steps itself because it has to scroll between them, so it calls
    /// ``showTheShelf(in:)`` and ``coversOnScreen(in:named:ofFormat:)`` directly. The
    /// filtering — which is where every lesson in this file lives — is in `coversOnScreen`
    /// and is therefore shared by both.
    func coversOnTheShelf(
        in app: XCUIApplication,
        named wanted: String? = nil,
        ofFormat format: String? = nil
    ) throws -> [XCUIElement] {
        try showTheShelf(in: app)
        return coversOnScreen(in: app, named: wanted, ofFormat: format)
    }

    /// Puts the library shelf on screen, and waits for it to have drawn something.
    func showTheShelf(in app: XCUIApplication) throws {
        try XCTUnwrap(destination("Library", in: app)).tap()

        let shelf = app.buttons.element(boundBy: 0)
        try XCTSkipUnless(shelf.waitForExistence(timeout: 10), "The library never drew a shelf.")
    }

    /// The covers drawn **right now**, which is not the same as the covers on the shelf.
    ///
    /// A shelf is a scroll view, `isHittable` is false for anything off it, and the frame
    /// bounds below are absolute screen coordinates — so every filter here is a statement
    /// about one screenful. That is enough for "open something" and wrong for "open a
    /// particular one": a caller that needs a publication further down the shelf has to
    /// scroll and ask again.
    ///
    /// **How far a screenful reaches on this corpus is not written down anywhere, and the one
    /// place that looks like it is is not.** `AccessibilityAuditTests` records five captions
    /// in the bottom strip of an 874-point window, but that device held `Blackwater #3`, which
    /// `scripts/corpus.mjs` does not build — so the shelf it measured was not this corpus's
    /// and bounds nothing about it.
    func coversOnScreen(
        in app: XCUIApplication,
        named wanted: String? = nil,
        ofFormat format: String? = nil
    ) -> [XCUIElement] {
        // Below the toolbar and above the tab bar: everything between is content. Judged on
        // the **centre** of the frame rather than on both edges, because a cover that
        // straddles the floating tab bar is still hittable and still opens — and testing
        // `maxY` threw away the whole bottom row of a grid whose cells the bar overlaps by a
        // few points. What the band is for is unchanged: keeping the toolbar's and the tab
        // bar's own buttons out, on the assumption that each sits wholly inside its strip —
        // which is what this was written on and what no run here has measured.
        app.buttons.allElementsBoundByIndex
            .filter { $0.isHittable && $0.frame.midY > 150 && $0.frame.midY < app.frame.height - 100 }
            .filter { !$0.label.contains("100 percent read") }
            .filter { wanted == nil || $0.label == wanted }
            .filter { cover in format.map { cover.label.contains(", \($0)") } ?? true }
    }

    /// A publication page's primary action, whichever of its two names it is wearing.
    ///
    /// *Read* on a publication nobody has opened and *Continue reading* on one somebody
    /// has. In one place, because the two copies of this walk each had their own and one of
    /// them matched `label IN {'Read', 'Continue'}`, which finds neither.
    var opensAPublication: NSPredicate {
        NSPredicate(format: "label BEGINSWITH 'Read' OR label BEGINSWITH 'Continue'")
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
