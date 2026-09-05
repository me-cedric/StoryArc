import XCTest

/// Getting an iPad into a known state, for the suites that photograph one.
///
/// Extracted from `SweepIpad.swift` when the split's own walks would have taken that file
/// past SwiftLint's 400-line cap. The seam is a real one rather than a place to cut: two
/// suites now need the same four moves — launch in a stated orientation, refuse to file a
/// compact window's frames under an iPad's name, reveal the sidebar, and reach a destination
/// through whatever control this window draws for it — and a second copy of any of them is a
/// second chance for one to point at the wrong thing.
///
/// An `extension XCTestCase`, which is how `SweepWalk.swift` and `AuditWalk.swift` already
/// share theirs. `XCTestCase` is an Objective-C class, so these names are dynamically
/// dispatched and a same-named member in a subclass is an override the compiler refuses —
/// which is why none of them is spelled `setUp`, `launch` or `open`.
@MainActor
extension XCTestCase {

    /// Launches in landscape, and refuses to photograph a compact window under an iPad's name.
    ///
    /// The orientation is set before the launch so the first frame is already landscape —
    /// rotating afterwards photographs a layout mid-animation as readily as after it.
    func landscape(contentSize: String? = nil, layout: String = "grid") throws -> XCUIApplication {
        try ipad(.landscapeLeft, contentSize: contentSize, layout: layout)
    }

    /// The same, the other way up.
    ///
    /// Portrait is the orientation an iPad is held in more than any other and the one this
    /// suite has never photographed: every iPad frame in `after-2026-08-30/` is portrait but
    /// predates the split, and every frame in `ios-sweep-2026-09-02/` is landscape. A pane
    /// layout is a question about width, so the narrow half of the answer needs its own frame.
    func portrait(contentSize: String? = nil, layout: String = "grid") throws -> XCUIApplication {
        try ipad(.portrait, contentSize: contentSize, layout: layout)
    }

    /// One launch, in a stated orientation, checked against the window it actually got.
    ///
    /// The width check is what stops a phone's frames being filed under an iPad's name. It is
    /// a skip rather than a failure: running the suite on a phone is a mistake about the
    /// device, not a defect in the app.
    private func ipad(
        _ orientation: UIDeviceOrientation,
        contentSize: String?,
        layout: String
    ) throws -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = sweepLaunch(contentSize: contentSize, layout: layout)
        hold(2)
        let wanted = orientation.isLandscape ? "landscape" : "portrait"
        let got = app.frame.width > app.frame.height ? "landscape" : "portrait"
        try XCTSkipUnless(
            got == wanted,
            "This device is \(Int(app.frame.width))×\(Int(app.frame.height)) — \(got) rather "
                + "than \(wanted), so these frames would be filed under a name they do not match."
        )
        // 700 in landscape; an iPad's portrait width starts at 768 and a phone's largest is
        // well under it, so one floor answers both orientations.
        try XCTSkipUnless(
            app.frame.width >= 700,
            "This window is \(Int(app.frame.width)) points wide, which is a compact shell "
                + "rather than an iPad's. Run this suite with --device pointed at an iPad."
        )
        return app
    }

    /// One destination, whatever a sidebar makes of it.
    ///
    /// **`destination(_:in:)` cannot see these.** It asks for a `tabBars` button, a button and
    /// a static text — which is the right set for a phone's tab bar and the wrong one for a
    /// regular window, where `.sidebarAdaptable` draws the same four entries as rows of a
    /// `List` and the platform calls them cells. Six iPad walks failed with "no Home" on a
    /// window whose sidebar had *Home* at the top of it.
    ///
    /// `control(_:in:)` already tries cells, and is what `AuditWalk` reaches for when a row is
    /// a `NavigationLink` rather than a button. The sidebar is asked to open first, because a
    /// window that starts with it collapsed has no rows to find.
    func go(to name: String, in app: XCUIApplication) throws {
        var entry = sidebarEntry(name, in: app)
        if entry == nil {
            try? showSidebar(in: app)
            hold(1)
            entry = sidebarEntry(name, in: app)
        }
        try XCTUnwrap(
            entry,
            "This window offers no way to \(name). Cells: "
                + "\(app.cells.allElementsBoundByIndex.prefix(12).map(\.label)). Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(12).map(\.label))"
        ).tap()
        hold(1)
    }

    /// The sidebar row for a destination, out of everything that carries its name.
    ///
    /// **The name is not unique and the first match is not the row.** The sidebar lists the
    /// four destinations and then a *Library* section header above *Recently added* and
    /// *Series* — so `app.cells["Library"]` binds to whichever the platform ordered first,
    /// and `control(_:in:)`, which asks each element type for its subscript, gave up when
    /// that one was a header nobody can tap. Every match is considered, and the first one a
    /// finger could reach is the row.
    func sidebarEntry(_ name: String, in app: XCUIApplication) -> XCUIElement? {
        let named = NSPredicate(format: "label == %@", name)
        for query in [app.cells.matching(named), app.buttons.matching(named)] {
            _ = query.firstMatch.waitForExistence(timeout: 3)
            if let hit = query.allElementsBoundByIndex.first(where: \.isHittable) { return hit }
        }
        return nil
    }

    /// Reveals the sidebar, whichever control this window draws for it.
    ///
    /// A regular window may open with the sidebar already out, or with the tab bar and a
    /// toggle. Both are the platform's decision rather than the app's, so this takes either
    /// and says which it found.
    ///
    /// **The shelf's own split removes its toggle**, deliberately —
    /// `LibraryPanes.swift` applies `.toolbar(removing: .sidebarToggle)` so that the only
    /// control matching "sidebar" in a window is the shell's. Before that there were two, a
    /// thumb apart, meaning different things, and this helper would have found either.
    func showSidebar(in app: XCUIApplication) throws {
        if app.buttons["All shelves"].exists { return }
        let toggle = app.buttons.matching(
            NSPredicate(format: "identifier CONTAINS[c] %@ OR label CONTAINS[c] %@", "sidebar", "sidebar")
        ).firstMatch
        if toggle.waitForExistence(timeout: 5), toggle.isHittable { toggle.tap() }
        hold(1.5)
        try XCTSkipUnless(
            app.buttons["All shelves"].waitForExistence(timeout: 5)
                || app.staticTexts["Library"].exists,
            "This window revealed no sidebar. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(25).map(\.label))"
        )
    }
}
