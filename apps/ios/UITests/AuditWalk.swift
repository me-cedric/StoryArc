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

    /// Every cover on the shelf a walk may open, in the order the shelf drew them.
    ///
    /// Split out of ``openFirstPublication(in:named:ofFormat:)`` so that
    /// ``openTheEpubReader(in:)`` can ask the same question — which covers are candidates —
    /// rather than growing a second answer to it. Each filter above is a lesson; two copies
    /// of them would be two sets of lessons, and this file exists because that already
    /// happened once.
    func coversOnTheShelf(
        in app: XCUIApplication,
        named wanted: String? = nil,
        ofFormat format: String? = nil
    ) throws -> [XCUIElement] {
        try XCTUnwrap(destination("Library", in: app)).tap()

        let shelf = app.buttons.element(boundBy: 0)
        try XCTSkipUnless(shelf.waitForExistence(timeout: 10), "The library never drew a shelf.")

        // Below the toolbar and above the tab bar: everything between is content.
        return app.buttons.allElementsBoundByIndex
            .filter { $0.isHittable && $0.frame.minY > 150 && $0.frame.maxY < app.frame.height - 100 }
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

    /// Opens the **reflowable** EPUB reader, and proves that is the reader it opened.
    ///
    /// `ofFormat: "EPUB"` is as close as the shelf can get and it is not close enough. A
    /// cover's spoken label carries its format and says nothing about how the book is laid
    /// out, while the app sends a **fixed-layout** EPUB to the *comic* reader — see
    /// `Publication.isReflowable`, which `ebook-reader` asks for, because a pre-paginated
    /// page has no typography to control and so no typography controls to audit.
    ///
    /// On this corpus "the first EPUB on the shelf" is not a coin toss but a certainty:
    /// `Bright Panels` and `Glasshouse` are both pre-paginated, and both sort before
    /// `Harbour Lights 01`, `Harbour Lights 02` and `The Long Field`, which are not. A walk
    /// that stops at the first EPUB reaches the comic reader every time and finds no theme
    /// control there — which is how the EPUB reader came to be written down as unreachable
    /// on a simulator, with two suites skipping to say so and a task list recording it as a
    /// platform limit.
    ///
    /// So this opens EPUBs in turn and stops at the one whose reader carries the theme
    /// control, which is the one control no other screen in the app has. Relaunching
    /// between attempts rather than closing the reader: leaving is a full-screen cover's
    /// own business, the comic reader's chrome fades after four seconds, and a launch is a
    /// single call that cannot half-succeed.
    ///
    /// One candidate skipping does not end the walk, and the skip at the end names every
    /// publication that was opened and every button that was on screen when it gave up. A
    /// check that gives up quietly is a check whose next reader derives all of this again.
    func openTheEpubReader(in app: XCUIApplication) throws {
        let candidates = try coversOnTheShelf(in: app, ofFormat: "EPUB").map(\.label)
        try XCTSkipUnless(!candidates.isEmpty, "This device's library holds no EPUB to open.")

        // `theme.title` in `EpubReaderFeature`, drawn as part of the chrome whether or not
        // the book has finished opening.
        let reading = app.buttons["Reading"]
        var opened: [String] = []
        for (attempt, candidate) in candidates.prefix(3).enumerated() {
            if attempt > 0 { app.launch() }
            // A hittable action, not the first in the hierarchy: this page has duplicate
            // entries and `firstMatch` can bind to one no finger could reach.
            guard (try? openFirstPublication(in: app, named: candidate)) != nil,
                  let action = app.buttons.matching(opensAPublication)
                      .allElementsBoundByIndex.first(where: \.isHittable)
            else { continue }
            action.tap()
            opened.append(candidate)
            // The reader's chrome is up when it appears and only a tap takes it away, so
            // this waits for the book to open rather than for a fade to be interrupted.
            if reading.waitForExistence(timeout: 15) { return }
        }
        throw XCTSkip(
            """
            No EPUB on this device opened the reflowable reader.
            Opened: \(opened)
            Not opened: \(candidates.prefix(3).filter { !opened.contains($0) })
            Buttons on screen: \(app.buttons.allElementsBoundByIndex.map(\.label))
            """
        )
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
