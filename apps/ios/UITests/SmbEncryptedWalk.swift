import XCTest

/// Task 18.3 of `close-the-audited-gaps`: an SMB 3 share that demands encryption, read from
/// the add sheet and from the source's detail screen.
///
/// The share is `scripts/smb-server.sh --encrypted` on port 4446 (`smb encrypt = required`).
/// A simulator shares the Mac's network, so `127.0.0.1` is the Mac. The user name is the Mac's
/// own, and the password is the fixture's, `lovelace`, which `smb-server.sh` prints. The walk
/// types both into the real form, so the credential goes through the app's own store.
///
/// The control is a share that nothing answers (port 4999): its detail screen must say that no
/// connection has been made, not that the share is encrypted or open.
@MainActor
final class SmbEncryptedWalkTests: XCTestCase {

    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let fixturePassword = "lovelace"

    /// The Mac's own user name, which `smb-server.sh` serves the share to. The simulator's
    /// processes run under another name, so it is read from the host's home folder.
    private static let macUser: String = {
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).lastPathComponent
    }()

    private static let noShares = #"{"sources":[],"tombstones":[]}"#

    private static let silentShare = """
    {"sources":[{"id":"7C2E5A10-3B44-4E8D-9A61-0F5D2B7E8C13","displayName":"Silent NAS",\
    "kind":"networkShare","locator":"smb://127.0.0.1:4999/Comics"}],"tombstones":[]}
    """

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCaptureAddShareEncrypted() throws {
        try addSheetConnected(contentSize: nil, named: "ios-add-share-encrypted")
    }

    func testCaptureAddShareEncryptedAtLargestText() throws {
        try addSheetConnected(contentSize: Self.largest, named: "ios-add-share-encrypted-ax5")
    }

    func testCaptureShareDetailEncrypted() throws {
        try detail(contentSize: nil, named: "ios-share-detail-encrypted")
    }

    /// Reads the share ``testCaptureShareDetailEncrypted`` registered, so run that first. At this
    /// size the system's password prompt is laid out differently and no tap of ours dismisses
    /// it, which is why this walk adds nothing.
    func testCaptureShareDetailEncryptedAtLargestText() throws {
        let app = sweepLaunch(contentSize: Self.largest)
        try openSettings(in: app)
        try XCTUnwrap(control("Your libraries", in: app), "No libraries row.").tap()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Comics'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "No Comics share. Run the default-size walk first.")
        _ = scrollTo(row, in: app)
        row.tap()
        hold(3)
        let test = app.buttons["Test connection"]
        XCTAssertTrue(scrollTo(test, in: app, swipes: 12), "The detail offers no reachable Test connection.")
        test.tap()
        hold(8)
        // The sentence sits above the actions, so scroll back up to it.
        for _ in 0..<6 { app.swipeDown() }
        let sentence = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'StoryArc reads this share'")).firstMatch
        _ = scrollTo(sentence, in: app, swipes: 4)
        hold(1)
        shutter(app, named: "ios-share-detail-encrypted-ax5")
    }

    func testCaptureShareDetailNotConnected() throws {
        let app = sweepLaunch(sources: Self.silentShare)
        try openTheShareDetail(named: "Silent NAS", in: app)
        hold(3)
        shutter(app, named: "ios-share-detail-not-connected")
    }

    // MARK: - Steps

    private func addSheetConnected(contentSize: String?, named name: String) throws {
        let app = sweepLaunch(contentSize: contentSize)
        try fillAndConnect(in: app)
        let line = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'encrypted'")).firstMatch
        _ = scrollTo(line, in: app)
        hold(1)
        shutter(app, named: name)
    }

    private func detail(contentSize: String?, named name: String) throws {
        let app = sweepLaunch(contentSize: contentSize, sources: Self.noShares)
        try fillAndConnect(in: app)
        try XCTUnwrap(hittable("Read from this folder", in: app), "No way to use the folder.").tap()
        // The system offers to save the password it just saw typed. Declined: the fixture
        // password is not worth a place in the Mac's keychain.
        let notNow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Not Now"]
        if notNow.waitForExistence(timeout: 12) { notNow.tap() }
        // The share is probed in the background once it is registered, and the detail screen
        // reads what that probe measured.
        hold(10)
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Comics'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The libraries list shows no Comics share.")
        // The prompt is drawn by another process, so no query of this app finds its button, and
        // while it is up the row is covered. Its Not Now sits left of centre, below the middle.
        for _ in 0..<3 where !row.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.33, dy: 0.615)).tap()
            hold(2)
        }
        _ = scrollTo(row, in: app)
        row.tap()
        hold(3)
        // The sentence is drawn from the last session the app measured. Adding a share browses
        // it through the sheet's own client, so the first frame of this screen says no
        // connection has been made; *Test connection* is what measures one.
        shutter(app, named: name.replacingOccurrences(of: "detail-encrypted", with: "detail-before-test"))
        try XCTUnwrap(hittable("Test connection", in: app), "The detail offers no Test connection.").tap()
        hold(8)
        shutter(app, named: name)
    }

    private func fillAndConnect(in app: XCUIApplication) throws {
        try openSettings(in: app)
        try XCTUnwrap(control("Your libraries", in: app), "No libraries row.").tap()
        hold(2)
        let add = try XCTUnwrap(hittable("Add a library", in: app, timeout: 8), "No Add a library control.")
        let shareRow = app.buttons["A computer on your network"]
        let attempts: [() -> Void] = [
            { add.tap() },
            { add.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap() },
            { add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1) },
            { add.doubleTap() },
        ]
        for attempt in attempts where !shareRow.exists {
            attempt()
            _ = shareRow.waitForExistence(timeout: 3)
        }
        try XCTUnwrap(
            hittable("A computer on your network", in: app),
            "No share row. Buttons: \(app.buttons.allElementsBoundByIndex.map(\.label))"
        ).tap()
        let host = app.textFields["Host"]
        XCTAssertTrue(host.waitForExistence(timeout: 8), "The share sheet has no Host field.")
        host.tap()
        host.typeText("127.0.0.1:4446")
        let share = app.textFields["Share"]
        share.tap()
        share.typeText("Comics")
        let user = app.textFields["User name"]
        user.tap()
        user.typeText(Self.macUser)
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText(Self.fixturePassword)
        let connect = app.buttons["Connect"]
        XCTAssertTrue(scrollTo(connect, in: app), "No reachable Connect button.")
        connect.tap()
        let line = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'encrypted'")).firstMatch
        XCTAssertTrue(
            line.waitForExistence(timeout: 20),
            "The share named no encryption state. Texts: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(25).map(\.label))"
        )
    }

    private func openTheShareDetail(named name: String, in app: XCUIApplication) throws {
        try openSettings(in: app)
        try XCTUnwrap(control("Your libraries", in: app), "No libraries row.").tap()
        let row = try XCTUnwrap(
            control(name, in: app) ?? hittable(name, in: app, timeout: 8),
            "No row named \(name). Labels: "
                + "\(app.descendants(matching: .any).allElementsBoundByIndex.prefix(40).map(\.label))"
        )
        row.tap()
    }
}
