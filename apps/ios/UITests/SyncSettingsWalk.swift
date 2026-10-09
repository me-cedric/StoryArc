import XCTest

/// `library-sync` task 5.3: the Sync section of Settings, in the states a reader reaches.
///
/// The share is `scripts/smb-server.sh --writable` on port 4448, or `--writable --encrypted` on
/// 4451 when `/tmp/w5sync/port` holds `4451`. A simulator shares the Mac's network, so
/// `127.0.0.1` is the Mac. The user name is the Mac's own and the password is the fixture's,
/// `lovelace`. The walk types both into the real add form, so the credential goes through the
/// app's own store.
///
/// Stateful and ordered, because the sync place is a device-local choice that outlives a launch:
/// each test turns sync off first, then reaches the state it photographs. The script that runs
/// them starts and stops the share between tests. The README of the frame set gives the order.
@MainActor
final class SyncSettingsWalkTests: XCTestCase {

    private static let fixturePassword = "lovelace"

    private static let macUser: String = {
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).lastPathComponent
    }()

    static var port: String {
        (try? String(contentsOfFile: "/tmp/w5sync/port", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "4448"
    }

    private var suffix: String { Self.port == "4451" ? "-encrypted" : "" }

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Frames

    /// Sync is off. Nothing is chosen, so the section offers the two ways to choose.
    func testCaptureSyncOff() throws {
        let app = try openSync()
        try turnOffIfOn(in: app)
        showSection(in: app)
        shutter(app, named: "sync-off")
    }

    /// The share is added through the form, then offered in the section's menu.
    func testCaptureSyncShareOffered() throws {
        let adding = sweepLaunch()
        try addShareIfAbsent(in: adding)
        adding.terminate()
        let app = try openSync()
        try turnOffIfOn(in: app)
        let menu = try XCTUnwrap(hittable("Use a shared folder", in: app), "No share menu in the Sync section.")
        _ = scrollTo(menu, in: app)
        menu.tap()
        hold(1)
        shutter(app, named: "sync-share-menu")
    }

    /// The share is chosen and the first sync ran: the place, the grey time, Sync now.
    func testCaptureSyncSynced() throws {
        let app = try openSync()
        try turnOffIfOn(in: app)
        try choose(shareNamed: "Sync", in: app)
        let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Synced at'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 25), "The sync did not finish. \(texts(in: app))")
        hold(12)
        showSection(in: app)
        shutter(app, named: "sync-synced\(suffix)")
    }

    /// The share does not answer: the grey line names the place. The server is stopped first.
    func testCaptureSyncUnreachable() throws {
        let app = try openSync()
        try XCTUnwrap(hittable("Sync now", in: app), "Sync is not on.").tap()
        let line = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'cannot be reached'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 40), "The place was not called unreachable. \(texts(in: app))")
        showSection(in: app)
        shutter(app, named: "sync-unreachable")
    }

    /// The share holds a file that is no library. The server runs again, with that file in it.
    func testCaptureSyncRefusedNotLibrary() throws {
        try refused(containing: "is not a StoryArc library", named: "sync-refused-not-library")
    }

    /// The share holds a library from a newer StoryArc.
    func testCaptureSyncRefusedNewer() throws {
        try refused(containing: "newer version", named: "sync-refused-newer")
    }

    /// The reader looks for sync in Settings search.
    func testCaptureSyncSearch() throws {
        let app = sweepLaunch()
        try openSettings(in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Settings has no search field.")
        field.tap()
        field.typeText("sync")
        hold(1.5)
        shutter(app, named: "sync-search-results")
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'sync'")).allElementsBoundByIndex
            .first { $0.isHittable && $0.elementType != .searchField }
        try XCTUnwrap(row, "Search for sync offered no row.").tap()
        hold(0.7)
        shutter(app, named: "sync-search-opened")
    }

    /// The system folder picker, then a folder in On My iPhone chosen as the place. The folder
    /// `Sync Folder` is made in the app's Documents by the script that runs the walk.
    func testCaptureSyncFolderPicker() throws {
        let app = try openSync()
        try turnOffIfOn(in: app)
        try XCTUnwrap(hittable("Choose a folder", in: app), "No Choose a folder.").tap()
        hold(3)
        shutter(app, named: "sync-folder-picker")
        // A picker that opens at On My iPhone shows the StoryArc folder alone, in the first cell.
        if app.staticTexts["On My iPhone"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.175, dy: 0.275)).tap()
            hold(2)
        }
        // The picker is drawn by another process. Its folders answer no query of this app, so
        // the third one, Sync Folder, is tapped where it is drawn.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.824, dy: 0.275)).tap()
        hold(2)
        shutter(app, named: "sync-folder-picker-inside")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.12)).tap()
        let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Synced at'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 25), "The folder was not synced. \(texts(in: app))")
        hold(3)
        showSection(in: app)
        shutter(app, named: "sync-folder-synced")
    }

    /// A new process after the folder was chosen: the place is still the folder, and a sync
    /// writes into it.
    func testCaptureSyncFolderRelaunch() throws {
        let app = try openSync()
        let place = app.staticTexts["Sync Folder"].firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 8), "The place is not the folder. \(texts(in: app))")
        try XCTUnwrap(hittable("Sync now", in: app), "Sync is not on.").tap()
        let line = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Synced at'")).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 25), "The folder was not synced. \(texts(in: app))")
        hold(3)
        showSection(in: app)
        shutter(app, named: "sync-folder-after-relaunch")
    }

    // MARK: - Steps

    private func refused(containing text: String, named name: String) throws {
        let app = try openSync()
        try XCTUnwrap(hittable("Sync now", in: app), "Sync is not on.").tap()
        let line = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 40), "The place was not refused. \(texts(in: app))")
        showSection(in: app)
        shutter(app, named: name)
    }

    private func openSync() throws -> XCUIApplication {
        let app = sweepLaunch()
        try openSyncSection(in: app)
        return app
    }

    private func openSyncSection(in app: XCUIApplication) throws {
        if !app.staticTexts["Settings"].exists { try openSettings(in: app) }
        try XCTUnwrap(control("Your libraries", in: app), "No libraries row.").tap()
        hold(2)
    }

    private func showSection(in app: XCUIApplication) {
        let header = app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Sync'")).firstMatch
        _ = scrollTo(header, in: app)
        hold(1)
    }

    private func turnOffIfOn(in app: XCUIApplication) throws {
        if let off = hittable("Turn off sync", in: app, timeout: 2) {
            off.tap()
            hold(1)
        }
    }

    private func choose(shareNamed name: String, in app: XCUIApplication) throws {
        let menu = try XCTUnwrap(hittable("Use a shared folder", in: app), "No share menu in the Sync section.")
        _ = scrollTo(menu, in: app)
        menu.tap()
        let item = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).allElementsBoundByIndex
            .first { $0.isHittable && $0.label != "Use a shared folder" }
        try XCTUnwrap(item, "The menu offers no share. \(texts(in: app))").tap()
    }

    /// The Sync share, added the way a reader adds one. A second run finds it and adds nothing.
    private func addShareIfAbsent(in app: XCUIApplication) throws {
        try openSettings(in: app)
        try XCTUnwrap(control("Your libraries", in: app), "No libraries row.").tap()
        hold(2)
        let known = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Sync'"))
        if known.allElementsBoundByIndex.contains(where: { $0.elementType == .cell }) { return }
        let add = try XCTUnwrap(hittable("Add a library", in: app, timeout: 8), "No Add a library control.")
        let shareRow = app.buttons["A computer on your network"]
        let attempts: [() -> Void] = [
            { add.tap() },
            { add.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap() },
            { add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1) },
        ]
        for attempt in attempts where !shareRow.exists {
            attempt()
            _ = shareRow.waitForExistence(timeout: 3)
        }
        try XCTUnwrap(hittable("A computer on your network", in: app), "No share row.").tap()
        let host = app.textFields["Host"]
        XCTAssertTrue(host.waitForExistence(timeout: 8), "The share sheet has no Host field.")
        host.tap()
        host.typeText("127.0.0.1:\(Self.port)")
        let share = app.textFields["Share"]
        share.tap()
        share.typeText("Sync")
        let user = app.textFields["User name"]
        user.tap()
        user.typeText(Self.macUser)
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText(Self.fixturePassword)
        let connect = app.buttons["Connect"]
        XCTAssertTrue(scrollTo(connect, in: app), "No reachable Connect button.")
        connect.tap()
        let use = hittable("Read from this folder", in: app, timeout: 25)
        try XCTUnwrap(use, "The share offered no folder to use.").tap()
        let notNow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Not Now"]
        if notNow.waitForExistence(timeout: 12) { notNow.tap() }
        hold(4)
        for _ in 0..<3 where app.buttons["Read from this folder"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.33, dy: 0.615)).tap()
            hold(2)
        }
    }

    private func texts(in app: XCUIApplication) -> String {
        "On screen: \(app.staticTexts.allElementsBoundByIndex.prefix(30).map(\.label))"
    }
}
