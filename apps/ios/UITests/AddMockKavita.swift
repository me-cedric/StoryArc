import XCTest

/// Adds the mock Kavita server through the app's own path, so a later capture has a server's
/// shelves to photograph.
///
/// **Not a guard, and not asserting anything about Kavita.** `a-server-shelf-shows-what-it-holds`
/// task 5.2 wants the Shelves screen photographed on iOS with a *server's* collections and
/// reading lists on it, and the six Android frames beside it were taken against the owner's
/// own server. No simulator has one. `scripts/kavita-server.mjs` is the mock this repository
/// already carries for exactly this — "so the walkthrough, enter a key, list libraries, open a
/// series, read a chapter, can be watched" — and it prints its own test key.
///
/// The address and the key are typed rather than injected because the key lives in the
/// Keychain, under `CredentialStore.reference(for:)`, and nothing outside the app can put it
/// there. So this walks the real form, which is also the only way the walkthrough is worth
/// watching.
///
/// Run it once, then run the capture tests. The source persists.
@MainActor
final class AddMockKavitaTests: XCTestCase {

    /// Where `node scripts/kavita-server.mjs <corpus> --port 5001` listens, and the key it
    /// prints. A simulator reaches the host on the loopback it shares.
    private static let address = "http://127.0.0.1:5001"
    private static let key = "storyarc-test-key"

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAddTheMockServer() throws {
        let app = sweepLaunch()

        // **Settings › Your libraries, not the Library toolbar.** Task 17.9 moved the
        // add-a-source control there — §6.2 of the design direction puts configuration in
        // Settings and nowhere else — and this walk kept tapping *Add books* on a toolbar
        // that no longer draws one, so it failed on a screen that was working.
        try openSettings(in: app)
        try openSetting("Your libraries", landmark: "Add a library", in: app)
        let addMenu = try XCTUnwrap(hittable("Add a library", in: app), "Your libraries offers no way to add one.")
        hold(1)
        addMenu.tap()

        // **A skip rather than a failure, and the skip is the finding.** The menu opens under
        // a finger — driven by hand on 2026-10-05 the five kinds appear at once — and does not
        // open under this synthetic tap on its button. Until somebody works out which element
        // the gesture wants, a red run here would say *the app has no Kavita sheet*, which is
        // false, and `AuditWalk.swift` argues at length against a check that can report the
        // wrong screen. The hand-driven route is in `docs/designs/screenshots/
        // browse-and-pins-2026-10-05/README.md`.
        let kavita = hittable("Kavita library", in: app, timeout: 8)
        try XCTSkipUnless(kavita != nil, "Add a library did not open its menu under a synthetic tap.")
        try XCTUnwrap(kavita).tap()
        XCTAssertTrue(
            app.staticTexts["API key"].waitForExistence(timeout: 8),
            "The Kavita sheet never appeared."
        )
        hold(1)

        // **By name, because each field now carries its own label.** A dump of this sheet on
        // 2026-09-11 reported `textFields: [""]` and `secureTextFields: [""]`: the words
        // *Address* and *API key* were adjacent `Text` and `.labelsHidden()` took the label
        // off the field itself. ``KavitaSheet`` now states each label again through
        // `.accessibilityLabel`, from the same key the visible `Text` reads, so a screen
        // reader names the field and this walk addresses it by that name.
        let address = app.textFields["Address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5), "The Kavita sheet has no address field.")
        address.tap()
        address.typeText(Self.address)

        let key = app.secureTextFields["API key"]
        XCTAssertTrue(key.exists, "The Kavita sheet has no API key field.")
        key.tap()
        key.typeText(Self.key)

        try XCTUnwrap(hittable("Connect", in: app), "The Kavita sheet offers no Connect.").tap()

        // The sheet answers with what it found before it offers to keep it, which is the
        // behaviour `sources` asks for: a reader sees the server's own name before they commit.
        let add = app.buttons["Add"]
        XCTAssertTrue(
            add.waitForExistence(timeout: 20),
            "Connect never produced an Add. Texts: \(app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label))"
        )
        add.tap()
        hold(6)

        // No assertion about the screen afterwards. Whether the source landed is a question
        // about `app.storyarc.sources`, which `simctl spawn defaults read` answers from
        // outside without guessing which element the shelf drew — and an earlier version of
        // this line failed on a stale element index rather than on anything true.
    }
}
