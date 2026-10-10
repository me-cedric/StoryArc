import XCTest

/// Apple's accessibility audit over the screen catalogue, with a gate that can fail.
///
/// `docs/designs/screen-catalogue.md` lists the screens that both platforms name the same way,
/// and the snapshot tests draw each one with fixture data. This class walks the real app to
/// each one a UI test can reach, and asks the platform's audit about it.
///
/// **What fails and what is reported.** The audit has many kinds of finding, and the older
/// audits in this target print all of them and fail on none (see `AccessibilityAuditTests`).
/// Here a control under 44 points, an element with no description and text under the contrast
/// floor on an element the audit names fail (`lighter-visual-check`, "Guidelines are checked by
/// machine"). A contrast fault that stands for now is on `knownContrastFaults` with its reason.
/// Clipped text, Dynamic Type and the rest are printed for a reader of the log. `auditCatalogue`
/// says why clipped text is among them, and `testAThirtyPointTargetFails` says why the 44 points
/// are measured here and not left to Apple's audit.
///
/// Every test skips, and does not fail, when the device cannot show its screen: a device with
/// no audiobook has no player, and a device with a library has no first-run Home. A suite that
/// reports a defect because its fixtures are missing is a suite nobody believes twice.
@MainActor
final class CatalogueAuditTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: - Home, library, search

    /// 1. Home with content.
    func testCatalogue01HomeWithContent() throws {
        let app = sweepLaunch()
        try XCTUnwrap(destination("Home", in: app), "The shell offers no Home tab.").tap()
        hold(2)
        try auditCatalogue(app, named: "01 Home")
    }

    /// 2. Home on a first run, when nothing has been added.
    func testCatalogue02HomeFirstRun() throws {
        let app = sweepLaunch(recents: "()")
        try XCTUnwrap(destination("Home", in: app), "The shell offers no Home tab.").tap()
        try XCTSkipUnless(
            app.staticTexts["Nothing here yet"].waitForExistence(timeout: 10),
            "This device holds a library, so its Home is not the first-run one."
        )
        try auditCatalogue(app, named: "02 Home first run")
    }

    /// 3. The library as a grid, and 17. its A to Z rail, which is drawn over it when the
    /// shelf holds more titles than a letter can help with.
    func testCatalogue03LibraryGridAndRail() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        waitForTheShelfToSettle(in: app)
        try auditCatalogue(app, named: "03 Library grid, with the rail when the shelf has one")
    }

    /// 4. The library as a list.
    func testCatalogue04LibraryList() throws {
        let app = sweepLaunch(layout: "list")
        try showTheShelf(in: app)
        waitForTheShelfToSettle(in: app)
        try auditCatalogue(app, named: "04 Library list")
    }

    /// 14. Search at rest.
    func testCatalogue14SearchAtRest() throws {
        let app = sweepLaunch()
        try XCTUnwrap(destination("Search", in: app), "The shell offers no Search tab.").tap()
        XCTAssertTrue(
            app.buttons["Everywhere"].waitForExistence(timeout: 10),
            "Search did not open a screen stating its scope."
        )
        hold(1.5)
        try auditCatalogue(app, named: "14 Search at rest")
    }

    /// 18. The library with the notice about files that could not be opened. Each of its two
    /// controls is a button of its own, 44 points high, which `auditCatalogue` measures.
    func testCatalogue18LibrarySkippedNotice() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        let show = app.buttons["Show"]
        try XCTSkipUnless(
            show.waitForExistence(timeout: 10),
            "This device's library skipped no file, so it shows no notice."
        )
        XCTAssertTrue(app.buttons["Dismiss"].exists, "The notice has no close button.")
        try auditCatalogue(app, named: "18 Library with the skipped notice")
    }

    // MARK: - The publication page

    /// 5. A publication page with a cover.
    func testCatalogue05PublicationWithCover() throws {
        let app = sweepLaunch(grouping: "issues")
        try openCover(titled: "Fine Print", in: app)
        hold(1.5)
        try auditCatalogue(app, named: "05 Publication page")
    }

    /// 6. A publication page with no cover, which draws the well in its place.
    func testCatalogue06PublicationWithoutCover() throws {
        let app = sweepLaunch(grouping: "issues")
        try openCover(titled: "Harbour Lights 01", in: app)
        hold(1.5)
        try auditCatalogue(app, named: "06 Publication page without a cover")
    }

    /// Opens a publication's page by the start of its cover's label, scrolling the shelf to it.
    ///
    /// By name, because "the first cover" is not a stable identity on a shelf that reorders, and
    /// the page has to prove it arrived by offering a way in.
    private func openCover(titled title: String, in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        let cover = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        var swipes = 0
        while !(cover.exists && cover.isHittable), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        try XCTSkipUnless(cover.exists && cover.isHittable, "This device's library holds no “\(title)”.")
        cover.tap()
        XCTAssertTrue(
            app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 10),
            "Opening “\(title)” reached no page with a way in."
        )
    }

    // MARK: - The player

    /// 8. The shelf with the compact player bar, and 7. the full player over it.
    func testCatalogue07And08Player() throws {
        // `launch()`, not `sweepLaunch()`: the seeded audiobook is a download record, and the
        // sweep pins that record to empty.
        let app = launch()
        try openAnAudiobook(in: app)
        try auditCatalogue(app, named: "08 Compact player bar")

        let wayIn = app.buttons["Open the player"].firstMatch
        try XCTSkipUnless(wayIn.waitForExistence(timeout: 5), "The bar offered no way into the player.")
        wayIn.tap()
        XCTAssertTrue(app.buttons["Chapters"].firstMatch.waitForExistence(timeout: 5), "The player never appeared.")
        try auditCatalogue(app, named: "07 Full player")
    }

    // MARK: - Settings

    /// 9. Settings, 10. its sources list and 11. one source.
    func testCatalogue09To11SettingsAndSources() throws {
        let app = sweepLaunch()
        try openSettings(in: app)
        try auditCatalogue(app, named: "09 Settings root")

        try openSetting("Your libraries", landmark: "Add a library", in: app)
        try auditCatalogue(app, named: "10 Sources list")

        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'title'")).allElementsBoundByIndex
            .first(where: \.isHittable)
        try XCTSkipUnless(row != nil, "Your libraries lists no source to open.")
        row?.tap()
        XCTAssertTrue(app.staticTexts["Status"].waitForExistence(timeout: 5), "The source opened no page of status.")
        try auditCatalogue(app, named: "11 Source detail")
    }

    /// 12. The sync section, at the foot of the sources list.
    func testCatalogue12SettingsSync() throws {
        let app = sweepLaunch()
        try openSettings(in: app)
        try openSetting("Your libraries", landmark: "Add a library", in: app)
        let section = app.staticTexts["Sync"]
        try XCTSkipUnless(scrollTo(section, in: app), "Your libraries shows no Sync section.")
        try auditCatalogue(app, named: "12 Sync section")
    }

    /// 13. Downloads, as the tab and as the settings group.
    func testCatalogue13Downloads() throws {
        let app = sweepLaunch()
        try XCTUnwrap(destination("Downloads", in: app), "The shell offers no Downloads tab.").tap()
        hold(1.5)
        try auditCatalogue(app, named: "13 Downloads tab")

        app.terminate()
        let settings = sweepLaunch()
        try openSettings(in: settings)
        try openSetting("Downloads and storage", landmark: "Space used by downloads", in: settings)
        try auditCatalogue(settings, named: "13 Downloads and storage")
    }

    // MARK: - The readers

    /// 15. The comic or PDF reader, with its chrome up.
    func testCatalogue15ReaderChrome() throws {
        let app = sweepLaunch(grouping: "issues")
        try openCover(titled: "Fine Print", in: app)
        let action = app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable)
        try XCTUnwrap(action, "The page offers no hittable way in.").tap()
        let close = app.buttons["Close"]
        if !close.waitForExistence(timeout: 10) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        try XCTSkipUnless(close.waitForExistence(timeout: 5), "The reader drew no chrome to audit.")
        try auditCatalogue(app, named: "15 Reader chrome")
    }

    /// 16. The reading themes sheet of the reflowable reader.
    func testCatalogue16ThemeSheet() throws {
        let app = sweepLaunch()
        try openTheEpubReader(in: app)
        let menu = app.buttons["Menu"]
        if !menu.waitForExistence(timeout: 5) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        try XCTSkipUnless(menu.waitForExistence(timeout: 5), "The EPUB reader drew no menu button.")
        menu.tap()
        for _ in 0..<5 where hittableRow("Reading themes", in: app, timeout: 1) == nil {
            app.swipeUp()
            hold(0.7)
        }
        try XCTUnwrap(hittableRow("Reading themes", in: app), "The reader's menu has no reading themes row.").tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Original")).firstMatch
                .waitForExistence(timeout: 8),
            "The theme sheet did not present its presets."
        )
        try auditCatalogue(app, named: "16 Theme sheet")
    }

    // MARK: - The gate proves it can fail

    /// A target of 30 points fails the gate, and one of 44 passes it.
    ///
    /// A gate is only worth its green if it can go red, and no screen of the app has a small
    /// control on purpose. A debug build draws six buttons, from 18 to 44 points, when it is
    /// launched with `-storyarc.audit.targets` (`App/AuditTargets.swift`).
    ///
    /// **Apple's audit does not fail a 30 point target, and this test says so.** Its hit-region
    /// check named the 18 point button and passed 24, 30, 36, 40 and 44 on iOS 26.2: its floor is
    /// about 24 points, not the 44 of the Human Interface Guidelines. So the gate measures the
    /// frames itself (`smallTargets`), and this test asks both: the platform audit must name the
    /// 18 point button, which proves the audit still runs, and the measure must name the 30 point
    /// button and leave the 44 point one.
    func testAThirtyPointTargetFails() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-storyarc.audit.targets"]
        app.launch()
        let thirty = app.buttons["audit.target.30"]
        XCTAssertTrue(thirty.waitForExistence(timeout: 15), "The debug build drew no 30 point target.")
        XCTAssertEqual(thirty.frame.height, 30, accuracy: 1)
        XCTAssertEqual(app.buttons["audit.target.44"].frame.height, 44, accuracy: 1)

        var flagged: [String] = []
        try app.performAccessibilityAudit(for: .hitRegion) { issue in
            flagged.append(issue.element?.identifier ?? "")
            return true
        }
        XCTAssertTrue(flagged.contains("audit.target.18"), "The platform audit named no 18 point target: \(flagged)")

        let measured = smallTargets(in: app).map(\.identifier)
        XCTAssertTrue(measured.contains("audit.target.30"), "The measure let a 30 point target pass: \(measured)")
        XCTAssertTrue(measured.contains("audit.target.40"), "The measure let a 40 point target pass: \(measured)")
        XCTAssertFalse(measured.contains("audit.target.44"), "The measure failed a 44 point target: \(measured)")
    }

    /// Text under the contrast floor fails the gate, and a known fault does not.
    ///
    /// The same debug build draws one label at about 1.5 to 1 (`App/AuditTargets.swift`). The
    /// platform audit must name it, and `catalogueVerdict` must fail it on a screen with no known
    /// fault for it, and pass it on the screen that lists it.
    func testFaintTextFails() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-storyarc.audit.targets"]
        app.launch()
        let faint = app.staticTexts["audit.contrast"]
        XCTAssertTrue(faint.waitForExistence(timeout: 15), "The debug build drew no faint label.")

        var verdicts: [CatalogueVerdict] = []
        try app.performAccessibilityAudit(for: .contrast) { issue in
            if issue.element?.identifier == "audit.contrast" {
                verdicts.append(catalogueVerdict(for: issue, on: "any screen"))
                verdicts.append(catalogueVerdict(for: issue, on: faintFault.screen, known: [faintFault]))
            }
            return true
        }
        XCTAssertEqual(verdicts, [.fail, .known("Faint on purpose")], "The gate did not fail the faint label.")
    }
}

/// The known fault `testFaintTextFails` lists, to prove that a listed fault is passed.
private let faintFault = KnownContrastFault(
    screen: "Audit targets", element: "Faint on purpose", why: "Faint on purpose."
)

/// The points a finger needs, from the Human Interface Guidelines.
private let minimumTarget: CGFloat = 44

@MainActor
extension XCTestCase {

    /// Every control the app draws that a finger cannot be sure to hit.
    ///
    /// Apple's hit-region audit has a floor near 24 points (see `testAThirtyPointTargetFails`), so
    /// the 44 point rule is measured here, on the accessibility frame, which is what the platform
    /// audit measures too. Left out, because their size is the system's and not the app's:
    ///
    /// - the buttons of a navigation bar, a toolbar and a tab bar, which iOS 26 draws 36 points
    ///   high in glass;
    /// - the sheet grabber;
    /// - the segments of a segmented control, which iOS draws 32 points high;
    /// - a control inside a list row of 44 points or more, where the row is the target: a picker
    ///   or a menu in a form;
    /// - switches, sliders and steppers, which the platform sizes.
    ///
    /// A control that the screen cuts is left out too, because its frame is the visible part and
    /// not the control. Hittability is not asked: it records a failure for a cover that scrolled
    /// half away.
    ///
    /// Each step has its own typed constant. The Xcode of the CI runner could not type-check
    /// the one chained expression this was before, and failed the build.
    fileprivate func smallTargets(in app: XCUIApplication) -> [XCUIElement] {
        let window: CGRect = app.windows.firstMatch.frame.insetBy(dx: 1, dy: 1)
        let barQueries: [XCUIElementQuery] = [app.navigationBars, app.toolbars, app.tabBars, app.segmentedControls]
        var bars: [CGRect] = []
        for query in barQueries {
            bars += query.descendants(matching: .button).allElementsBoundByIndex.map(\.frame)
        }
        let rows: [CGRect] = app.cells.allElementsBoundByIndex.map(\.frame).filter { $0.height >= minimumTarget }
        var controls: [XCUIElement] = app.descendants(matching: .button).allElementsBoundByIndex
        controls += app.descendants(matching: .link).allElementsBoundByIndex
        return controls.filter { control in
            guard control.exists, control.label != "Sheet Grabber" else { return false }
            let frame: CGRect = control.frame
            guard !frame.isEmpty, window.contains(frame) else { return false }
            guard min(frame.width, frame.height) < minimumTarget - 0.5 else { return false }
            guard !bars.contains(frame) else { return false }
            return !rows.contains { $0.contains(frame) }
        }
    }

    /// The catalogue's gate.
    ///
    /// **Fails:** a control under 44 points on either side, a hit region the platform names, an
    /// element with no description, and text under the contrast floor on an element the audit
    /// names (`catalogueVerdict`). A steady known fault that no longer occurs fails too, so the
    /// list drains. **Reported:** every other finding. Clipped text is reported because the audit
    /// cannot tell text that a scroll view cuts at its edge from text that a layout clips, and it
    /// names no element for most of what it finds.
    fileprivate func auditCatalogue(_ app: XCUIApplication, named screen: String) throws {
        var failing: [String] = []
        var reported: [String] = []
        var knownSeen: Set<String> = []
        let window: CGRect = app.windows.firstMatch.frame
        var bars: [CGRect] = app.tabBars.allElementsBoundByIndex.map(\.frame)
        bars += app.toolbars.allElementsBoundByIndex.map(\.frame)
        bars += app.navigationBars.allElementsBoundByIndex.map(\.frame)
        try app.performAccessibilityAudit(for: .all) { issue in
            // The first line of the description names the element: type, frame, identifier, label.
            let element = issue.element?.debugDescription.split(separator: "\n").first.map(String.init)
            let line = "\(issue.compactDescription). \(element ?? "No element reported.")"
            switch catalogueVerdict(for: issue, on: screen, window: window, bars: bars) {
            case .fail:
                failing.append(line)
            case .known(let name):
                knownSeen.insert(name)
                reported.append("  • known fault: \(line)")
            case .report:
                reported.append("  • \(line)")
            }
            return true
        }
        if !reported.isEmpty {
            print("Catalogue audit — \(screen): \(reported.count) finding(s) reported, not failed")
            for line in reported { print(line) }
        }
        // XCTFail, not `return false`: the message the platform records names no element.
        for line in failing {
            XCTFail("\(screen): \(line)")
        }
        let gone = knownContrastFaults.filter { $0.screen == screen && $0.isSteady && !knownSeen.contains($0.element) }
        for fault in gone {
            XCTFail(
                "\(screen): the known contrast fault on “\(fault.element)” no longer occurs. "
                    + "Remove it from knownContrastFaults."
            )
        }

        for target in smallTargets(in: app) {
            let size = "\(Int(target.frame.width)) by \(Int(target.frame.height))"
            XCTFail("\(screen): “\(target.label)” is \(size) points. A finger needs 44. \(target.debugDescription)")
        }
    }
}
