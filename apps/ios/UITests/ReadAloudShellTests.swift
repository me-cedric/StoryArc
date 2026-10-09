import XCTest

/// What the shell does around a running voice: it carries on after the reader closes (0.1),
/// and it reserves no height when there is no session (2.3).
///
/// `read-aloud-beyond-the-reader` tasks 0.1 and 2.3. The voice here is a simulator's, so the
/// answer is simulator-only: what is read is the session's own state, the bar's control and
/// title, and not the sound. The lock-screen half stays on the device checklist.
@MainActor
final class ReadAloudShellTests: XCTestCase {

    /// The four destinations, in tab order.
    private static let destinations = ["Home", "Library", "Downloads", "Search"]

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Closes the reader while the voice speaks, and the bar still says Pause four seconds later.
    ///
    /// `ReadAloudPlayerTests.speakAndLeaveTheReader` pauses first, so it cannot tell a voice that
    /// carries on from one that stopped when the reader went. This one never pauses.
    func testTheVoiceCarriesOnAfterTheReaderCloses() throws {
        let walk = try speakAloud(opening: "Harbour Lights 01", pausing: false)
        let app = walk.app
        bringBackTheFullBar(in: app)
        let before = barLine(in: app)
        XCTAssertTrue(
            app.buttons["Pause"].firstMatch.exists,
            "The reader is closed and the bar offers no Pause, so the voice is not running. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
        )

        hold(4)

        XCTAssertTrue(
            app.buttons["Pause"].firstMatch.exists,
            "Four seconds after the reader closed the bar no longer offers Pause. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
        )
        let after = barLine(in: app)
        XCTAssertEqual(after.title, before.title, "The bar names another book after four seconds.")
        XCTAssertFalse(after.title.isEmpty, "The bar draws no title.")
        shutter(app, named: "voice-running-reader-closed")
        add(XCTAttachment(string: "title: \(before.title) -> \(after.title); line: \(before.chapter) -> \(after.chapter)"))
    }

    /// Four destinations, each with no session and with one, and the tab bar the same height.
    ///
    /// The pair is what proves `tabViewBottomAccessory(isEnabled:)` withholds the height and
    /// not only the bar. The baseline is taken before any session exists. After the session
    /// is ended, every destination has that baseline frame again and no control of a bar.
    func testTheShellReservesNothingWithoutASession() throws {
        let none = sweepLaunch(formats: readAloudFormats, grouping: "issues")
        var baseline: [String: CGRect] = [:]
        for name in Self.destinations {
            try XCTUnwrap(destination(name, in: none)).tap()
            hold(1.5)
            XCTAssertFalse(none.buttons["Stop"].exists, "\(name) draws a bar with no session.")
            XCTAssertFalse(slotAboveTheTabBar(in: none), "\(name) holds an empty slot above the tab bar with no session.")
            baseline[name] = none.tabBars.firstMatch.frame
            shutter(none, named: "shell-\(name.lowercased())-no-session")
        }

        let app = try speakAloud(opening: "Harbour Lights 01").app
        for name in Self.destinations {
            try XCTUnwrap(destination(name, in: app)).tap()
            bringBackTheFullBar(in: app)
            XCTAssertTrue(app.buttons["Stop"].firstMatch.waitForExistence(timeout: 5), "\(name) draws no bar with a session.")
            shutter(app, named: "shell-\(name.lowercased())-session")
            add(XCTAttachment(string: "\(name) tab bar with a session: \(app.tabBars.firstMatch.frame); baseline: \(String(describing: baseline[name]))"))
        }

        app.buttons["Stop"].firstMatch.tap()
        hold(1.5)
        for name in Self.destinations {
            try XCTUnwrap(destination(name, in: app)).tap()
            hold(1.5)
            XCTAssertFalse(app.buttons["Stop"].exists, "\(name) still draws a bar after the session ended.")
            XCTAssertFalse(app.buttons["Open the player"].exists, "\(name) still offers the player after the session ended.")
            XCTAssertFalse(slotAboveTheTabBar(in: app), "\(name) holds an empty slot above the tab bar after the session ended.")
            XCTAssertEqual(
                app.tabBars.firstMatch.frame, baseline[name],
                "\(name): the tab bar is not where it was before any session. The slot is still reserved."
            )
        }
    }

    /// Whether something wide and bar-high sits just above the tab bar: the slot, with a bar in it or not.
    ///
    /// Measured on 2026-10-09 with `isEnabled:` forced true: the empty capsule is an `Other`
    /// 378 x 48 pt whose bottom edge sits eight points above the tab bar. The tab bar's own frame
    /// does not move, so the frame alone cannot see it.
    private func slotAboveTheTabBar(in app: XCUIApplication) -> Bool {
        let top = app.tabBars.firstMatch.frame.minY
        return app.descendants(matching: .other).allElementsBoundByIndex.contains {
            $0.frame.width > 300 && $0.frame.height < 70 && $0.frame.maxY <= top && $0.frame.maxY > top - 20
        }
    }

    /// A minimised tab bar holds the bar inline. A swipe down on the screen brings the full bar back.
    private func bringBackTheFullBar(in app: XCUIApplication) {
        if !app.buttons["Open the player"].firstMatch.waitForExistence(timeout: 3) { app.swipeDown() }
        _ = app.buttons["Open the player"].firstMatch.waitForExistence(timeout: 5)
    }

    /// The bar's book title and its chapter line.
    private func barLine(in app: XCUIApplication) -> (title: String, chapter: String) {
        let wayBack = app.buttons["Back to the book"].firstMatch
        _ = wayBack.waitForExistence(timeout: 5)
        return (wayBack.staticTexts.firstMatch.label, wayBack.value as? String ?? "")
    }
}
