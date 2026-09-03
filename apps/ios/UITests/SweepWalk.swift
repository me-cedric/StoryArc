import XCTest

// The walk the September sweep shares: a launch that says what state the device is in, a
// shutter, and a settle.
//
// It is separate from `AuditWalk.swift` because it answers a different question. That file
// finds things — a destination, a cover, the action that opens a publication — and every
// caller of it takes the device as it is. A *sweep* cannot: an inventory of every surface has
// to reach the ones that are absent unless something is arranged, and the arranging is what
// is shared here.
//
// ## Why the appearance arrives as a launch argument
//
// `capture-ios.mjs` sets the **simulator's** appearance, on the reasoning `AGENTS.md` §6
// records: the app's settings are one JSON blob under one key, so there is no launch argument
// for the theme alone, and the device is the only lever. The reasoning is sound and the
// conclusion was too narrow — the blob itself is injectable, and `UserDefaults`'s argument
// domain outranks the standard one, so `-app.storyarc.settings <hex>` hands the app a whole
// settings value for one launch and leaves nothing behind.
//
// **This matters because it was silently wrong on this device.** The simulator carried
// `appearance: "oledDark"` in its stored settings, so `--appearance light` set the device to
// light and the app drew true black over it. Every light capture taken that way would have
// been a dark one under a light filename, and nothing in the run would have said so. Passing
// `system` explicitly is what makes the harness's flag authoritative again — the app follows
// the device because this launch told it to, not because nobody had changed it.
//
// The `-dark` suffix on the filenames still comes from the harness, so a walk here must be
// launched under `--appearance dark` to be filed as dark. Injecting `dark` instead would
// produce a dark picture under a light name, which is the failure this paragraph exists to
// prevent.

@MainActor
extension XCTestCase {

    /// Launches the app with the device state a capture needs, and nothing else changed.
    ///
    /// - Parameters:
    ///   - contentSize: a `UIContentSizeCategory` name, for the accessibility passes.
    ///   - appearance: an ``AppearanceMode`` raw value. `system` — the default — is what
    ///     lets `--appearance` decide, and is what every light/dark pair wants.
    ///   - natural: the Natural theme, which is a second axis rather than a fifth
    ///     appearance and therefore a key of its own.
    ///   - downloads: a `[StoredDownload]` JSON array, for the surfaces that do not exist
    ///     without a transfer record. Nothing on this device has one, and a queue
    ///     photographed by starting a real download would need a server, a network and a
    ///     file that takes long enough to photograph.
    ///   - language: a BCP-47 tag for the app's own language override.
    ///   - searchScope: `everywhere` or `onThisDevice`, the search screen's own axis.
    ///   - layout: `grid` or `list`, the shelf's own persisted layout.
    ///
    /// ## Every shelf choice is stated, and that is what makes a capture repeatable
    ///
    /// **The first version passed only what a test wanted and inherited the rest.** Every
    /// shelf choice this app has — the layout, the availability axis, the download group, the
    /// query — is persisted in `UserDefaults` because `library-browsing` requires it to
    /// "persist until changed", so a walk that changed one left it changed for the next walk
    /// *and* the next run. Measured: `testCaptureCompactList` chose List, and the
    /// `library-grid` frame taken four tests later — under a filename saying grid — is a
    /// picture of a list. An unread filter set by one run survived into the next and filled
    /// the filter control on a shelf nobody had filtered.
    ///
    /// So every key is passed on every launch, whether the test cares or not. The argument
    /// domain outranks the standard one, so this is the state the app starts in; what a walk
    /// then changes it still changes, in memory, for that session only.
    func sweepLaunch(
        contentSize: String? = nil,
        appearance: String = "system",
        natural: Bool = false,
        downloads: String = "[]",
        language: String? = nil,
        searchScope: String = "everywhere",
        availability: String = "everywhere",
        layout: String = "grid",
        recents: String = "(\"Harbour\", \"Vermillion\", \"Fine Print\")"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-app.storyarc.settings", asPlistData(settingsJSON(appearance, language)),
            "-storyarc.appearance.natural", natural ? "YES" : "NO",
            // The transfer record. `[]` rather than absent, so a queue one walk injected is
            // not still in the frame of the next one.
            "-app.storyarc.downloads", asPlistData(downloads),
            "-app.storyarc.libraryQuery", asPlistData(queryJSON()),
            "-app.storyarc.libraryAvailability", availability,
            "-app.storyarc.searchScope", searchScope,
            "-app.storyarc.libraryDownloadFilter", "either",
            // Per-scope, and `all` is `LibraryScope.allSources.storageKey` — the shelf and
            // the search surface both read that one.
            "-app.storyarc.libraryLayout.all", layout,
            // The recent searches, which are also **how a term gets into the field**.
            //
            // Not through the query: `LibraryPreferences.query()` clears `search` on restore
            // on purpose — "a filter is a decision that outlives a session; a half-typed
            // search is not" — so an injected term is discarded before any screen sees it,
            // and the search walks photographed the at-rest screen under names saying
            // *results* and *no results*. Not through the keyboard either: typing into the
            // simulator goes through a French layout and garbles ASCII.
            //
            // A recent search is a control that sets `model.query.search` directly, and
            // `LibrarySearchSurface` asks on `.onChange(of:initial:)` — so tapping one runs
            // the term exactly as typing it would. `Harbour` matches; `Vermillion` matches
            // nothing on this corpus.
            // `()` — an empty old-style plist array — is what the first-run walks pass, so
            // the at-rest search screen can reach its *nothing to suggest* branch. It is
            // gated on the recents being empty as well as the suggestions.
            "-app.storyarc.librarySearches", recents,
        ]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    /// The shelf query with every axis at rest: no filters, sorted by title, ascending.
    ///
    /// The field's shape rather than `LibraryQuery`'s encoder, for the reason
    /// ``settingsJSON(_:_:)`` gives: the UI-test bundle cannot see `StoryArcCore`.
    /// `LibraryQueryTests` pins the encoding on the host side.
    ///
    /// **It carries no search term and cannot.** `LibraryPreferences.query()` clears `search`
    /// on the way out of storage on purpose. A term reaches a screen by tapping a recent
    /// search — see `SweepSearchTests.run(_:in:)`.
    private func queryJSON() -> String {
        """
        {"publishers":[],"sort":"title","scope":"all","readStates":[],"years":{},\
        "ascending":true,"tags":[],"search":"","genres":[],"formats":[],"languages":[]}
        """
    }

    /// The settings blob, with everything but the appearance left at its default.
    ///
    /// Written out here rather than encoded from `AppSettings`: the UI-test bundle cannot see
    /// `StoryArcCore`, and a test that could would be asserting the encoder rather than
    /// using it. `AppSettingsTests` pins the shape on the host side.
    private func settingsJSON(_ appearance: String, _ language: String?) -> String {
        let tag = language.map { ",\"language\":\"\($0)\"" } ?? ""
        return """
        {"appearance":"\(appearance)","turnPagesWithVolumeButtons":false,\
        "linkReadingThemeToAppearance":false,"downloadOverWifiOnly":false,\
        "removeDownloadsAfterFinishing":false\(tag)}
        """
    }

    /// A string as the old-style property-list data literal `UserDefaults` reads.
    ///
    /// The argument domain parses each value as a property list, and `<hex>` is how that
    /// grammar spells `Data` — which is what `SettingsStore` and `DownloadStore` both ask
    /// `UserDefaults` for. Anything else arrives as a string and both stores read it as
    /// absent, which looks exactly like a launch argument that was ignored.
    private func asPlistData(_ text: String) -> String {
        "<" + text.utf8.map { String(format: "%02x", $0) }.joined() + ">"
    }

    /// Attaches a screenshot under the name `capture-ios.mjs` files it by.
    ///
    /// `.keepAlways`, because an attachment on a passing test is discarded by default and a
    /// capture suite whose every test passes would produce nothing at all.
    ///
    /// Named `shutter` rather than `attach` on purpose: `XCTestCase` is an Objective-C class,
    /// so an extension's methods are dynamically dispatched and a same-named member in a
    /// subclass is an override the compiler refuses. `ScreenshotTests`,
    /// `PlayerScreenshotTests` and `AppIconCaptureTests` each own an `attach` and a `settle`.
    /// Overloading it is not an option: `XCTestCase` is an Objective-C class, so
    /// `shutter(_:named:)` twice is one selector twice and the compiler refuses.
    func shutter(_ app: XCUIApplication, named name: String) {
        shutter(shot: app.screenshot(), named: name)
    }

    func shutter(shot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits, then lets the caller photograph.
    ///
    /// Chrome animates in and out, and a screenshot taken during either is a picture of a
    /// half-faded bar. `Thread.sleep` blocks the main actor and starves the run loop the
    /// animation needs, so this parks on an expectation instead.
    func hold(_ seconds: TimeInterval) {
        let settled = XCTestExpectation(description: "waited \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { settled.fulfill() }
        wait(for: [settled], timeout: seconds + 3)
    }

    /// Home → Settings, asserting it arrived.
    ///
    /// The rows are `NavigationLink`s in a `List`, which surface as cells rather than
    /// buttons — see ``control(_:in:)``.
    @discardableResult
    func openSettings(in app: XCUIApplication) throws -> XCUIApplication {
        try XCTUnwrap(control("Settings", in: app), "Home has no way into Settings.").tap()
        XCTAssertTrue(
            app.staticTexts["Settings"].waitForExistence(timeout: 5),
            "Tapping Settings did not open a screen headed Settings."
        )
        return app
    }

    /// One row of Settings, opened, with the screen it leads to proved to be on top.
    ///
    /// `landmark` is a string only the destination has. It is the whole reason this helper
    /// exists rather than two lines at each call site: seven `XCTFail`s saying "Settings has
    /// no row called …" were once swallowed by one broad `XCTExpectFailure`, and a capture
    /// that photographs the list it failed to leave is worse than no capture.
    func openSetting(_ row: String, landmark: String, in app: XCUIApplication) throws {
        try XCTUnwrap(control(row, in: app), "Settings has no \(row) row.").tap()
        let arrived = app.staticTexts[landmark].waitForExistence(timeout: 5)
            || app.buttons[landmark].waitForExistence(timeout: 2)
            || app.cells[landmark].waitForExistence(timeout: 2)
        XCTAssertTrue(
            arrived,
            "\(row) did not lead to a screen carrying “\(landmark)”. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(30).map(\.label))"
        )
    }

    /// Scrolls the screen until a named element is both there and reachable.
    ///
    /// A `List` renders lazily, so an element below the fold does not exist rather than
    /// existing off-screen — and `isHittable` is the half that matters for a control the
    /// capture is meant to show. Bounded, and it says how far it got.
    @discardableResult
    func scrollTo(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 8) -> Bool {
        for _ in 0..<swipes {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// Opens the library's *View* menu, and proves it opened.
    ///
    /// The toolbar's four items are two icons in a capsule between *Select* and *Add books*,
    /// and neither icon says which is which — see `LibraryToolbar.swift`. The label is the
    /// only stable handle, and the landmark is a picker row that exists nowhere else.
    func openViewMenu(in app: XCUIApplication) throws {
        try XCTUnwrap(hittable("View", in: app), "The library toolbar offers no View menu.").tap()
        XCTAssertTrue(
            app.buttons["Grid"].waitForExistence(timeout: 5)
                || app.staticTexts["Show as"].waitForExistence(timeout: 2),
            "The View menu did not open: it offered neither a layout picker nor its label."
        )
    }

    /// Opens the library's *Filter* menu, and proves it opened.
    func openFilterMenu(in app: XCUIApplication) throws {
        try XCTUnwrap(hittable("Filter", in: app), "The library toolbar offers no Filter menu.").tap()
        XCTAssertTrue(
            app.buttons["Read or unread"].waitForExistence(timeout: 5),
            "The Filter menu did not open: it offered no read-state group."
        )
    }

    /// A named button a finger could actually reach.
    ///
    /// `firstMatch` is not enough on these screens: a menu label and the row it opens can
    /// share a name, and a toolbar item behind a presented sheet still exists.
    ///
    /// **It waits, and that is not a nicety.** `allElementsBoundByIndex` resolves the query
    /// at once, so a submenu row asked for the instant its parent was tapped is not there
    /// yet — and this returned `nil` for *Unread* in one walk and found it in the next,
    /// which is a flake that reads as a missing control. The wait is on the query's own
    /// `firstMatch`; the hittability filter still runs against every match afterwards.
    func hittable(_ name: String, in app: XCUIApplication, timeout: TimeInterval = 5) -> XCUIElement? {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", name))
        _ = matches.firstMatch.waitForExistence(timeout: timeout)
        return matches.allElementsBoundByIndex.first(where: \.isHittable)
    }

    /// A named control whose label may carry its own value after the name.
    ///
    /// The reader's menu is built from rows that state a name *and* the current setting —
    /// `LabeledContent { Text(chosen) } label: { Text("Transition") }`, a menu-styled `Picker`
    /// with its selection beside it, a *Contents* row with the page position on a second line
    /// — and `.accessibilityElement(children: .combine)` joins them into one label. So the
    /// element is called `Transition, Slide` and an exact-label lookup finds nothing, on a
    /// screen that is showing the row.
    ///
    /// A prefix rather than `CONTAINS`, so *Search* cannot match *Search this PDF*.
    func hittableRow(_ name: String, in app: XCUIApplication, timeout: TimeInterval = 5) -> XCUIElement? {
        let matches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name))
        _ = matches.firstMatch.waitForExistence(timeout: timeout)
        return matches.allElementsBoundByIndex.first(where: \.isHittable)
    }

    /// A control in a reader's chrome, with the chrome actually up.
    ///
    /// **A centre tap toggles, and that is what made eight walks fail at once.** Both readers
    /// fade their chrome out after four seconds, so a walk that arrives, does something for
    /// three seconds and then asks whether the chrome is there gets a half-faded answer:
    /// `exists` is true and `isHittable` is false. Tapping the centre *then* toggles the
    /// chrome **off**, and the control the walk was after never appears — eight captures of
    /// the comic reader's menu reported "the reader revealed no menu to open" on a reader
    /// that had drawn one twice.
    ///
    /// So the fade is waited out rather than raced: if the control is already reachable, take
    /// it; otherwise let the countdown finish, tap once, and wait. Three attempts, because a
    /// tap that lands during the *fade-in* is the same trap in the other direction.
    func revealed(_ name: String, in app: XCUIApplication, attempts: Int = 3) -> XCUIElement? {
        for _ in 0..<attempts {
            if let hit = hittable(name, in: app, timeout: 1) { return hit }
            // Past the four seconds `comic-reader` gives the chrome, so its state is known.
            hold(5)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            hold(1)
        }
        return hittable(name, in: app, timeout: 2)
    }

    /// The covers a sweep may tap, and nothing that merely sits where a cover does.
    ///
    /// ``coversOnScreen(in:named:ofFormat:)`` filters `app.buttons` by position — a band
    /// between the toolbar and the tab bar — and on this device that band contains the
    /// skipped-publications notice's two controls. So a walk that asked for "the covers" and
    /// tapped the first two tapped *What couldn't be opened* and *Dismiss*, and the shelf
    /// stayed at `0 selected` while the walk reported the covers as unselectable.
    ///
    /// A cover's spoken label carries its format — `LibraryMarks.spoken([title, subtitle,
    /// format, …])` — and no notice does, so asking the shared helper for one format at a
    /// time is a filter it already has. Every format on the shelf, so this is still "the
    /// covers" rather than "the EPUBs".
    func realCovers(in app: XCUIApplication) -> [XCUIElement] {
        // `PublicationFormat.displayName`'s nine, which is the whole set — a cover with a
        // format this misses would be silently unpickable, which is the failure above again.
        let formats = ["CBZ", "CBR", "CB7", "CBT", "EPUB", "PDF", "Folder", "Audiobook", "Audio folder"]
        // **One snapshot of the hierarchy, not nine.** Asking the shared helper once per
        // format enumerated every button on the screen nine times over, and at
        // `accessibilityExtraExtraExtraLarge` — where a cell is 1.4 times wider, so the shelf
        // is taller and the tree deeper — that was most of a twenty-two-minute suite. Same
        // filter, one round trip to the app.
        let ceiling = app.frame.height - 100
        let isACover = { (element: XCUIElement) in
            element.isHittable
                && element.frame.midY > 150
                && element.frame.midY < ceiling
                && formats.contains { element.label.contains(", \($0)") }
        }
        let asButtons = app.buttons.allElementsBoundByIndex.filter(isACover)
        if !asButtons.isEmpty { return asButtons }
        // **In selection mode a cover may not be a button.** `CoverCell` drops the
        // `NavigationLink` for a plain view with an `onTapGesture` while the shelf is
        // picking, so what the accessibility tree calls it is the platform's decision rather
        // than this app's. Falling back rather than asserting: a walk that reported "no
        // covers" on a shelf full of them sent the last reader to the wrong file.
        return app.otherElements.allElementsBoundByIndex.filter(isACover)
    }
}
