import XCTest

/// The source whose credential stopped working, and the sheet that offers to mend it.
///
/// `source-lifecycle` task 4.2 wants the reconnect sheet photographed: the add sheet
/// re-opened by the detail screen's *Reconnect* row, with the address filled and the secret
/// blank. It sat open because "no walk and no route on either platform", and under that
/// because nothing could produce a refused credential on a simulator.
///
/// `scripts/kavita-server.mjs` can. Add the mock with its own key, then serve the same
/// corpus from a copy whose `API_KEY` differs, and the key the app is holding is refused
/// with a 401 — which is a credential that stopped working rather than a server that went
/// away, and it is the one state `SourceDiagnosis.of` offers *Reconnect* for.
///
/// Run `AddMockKavitaTests` first, then rotate the server's key, then this.
@MainActor
final class RejectedCredentialTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The detail screen of the source whose key is refused.
    func testCaptureRefusedSourceDetail() throws {
        let app = try openTheServer()
        hold(3)
        shutter(app, named: "source-refused-detail")
    }

    /// The reconnect sheet, which is the add sheet re-opened with the address kept.
    func testCaptureReconnectSheet() throws {
        let app = try openTheServer()
        hold(3)
        try XCTUnwrap(
            hittable("Reconnect", in: app) ?? control("Reconnect", in: app),
            """
            The detail screen offers no Reconnect. `SourceDiagnosis.of` offers it only for a \
            refused credential, so either the probe has not run yet or the server is answering \
            the key after all. Rows: \(app.staticTexts.allElementsBoundByIndex.prefix(14).map(\.label))
            """
        ).tap()
        hold(2)
        shutter(app, named: "source-reconnect-sheet")
    }

    /// Settings → Your libraries → the mock server.
    private func openTheServer() throws -> XCUIApplication {
        let app = sweepLaunch()
        try openSettings(in: app)
        try XCTUnwrap(control("Your libraries", in: app), "no libraries row").tap()
        let row = try XCTUnwrap(
            app.buttons.allElementsBoundByIndex.first { $0.label.contains("127.0.0.1") }
                ?? app.cells.allElementsBoundByIndex.first { $0.label.contains("127.0.0.1") },
            """
            No row names the mock server. Run AddMockKavitaTests first. \
            Rows: \(app.buttons.allElementsBoundByIndex.prefix(14).map(\.label))
            """
        )
        row.tap()
        XCTAssertTrue(
            app.staticTexts["Status"].waitForExistence(timeout: 8),
            "The source did not open a page stating its status."
        )

        // **Ask, then wait for the answer.** The screen opens on *Connecting*, because
        // `test(_:)` marks the source before it asks — which is the behaviour
        // `SourceRefreshWiringTests` pins. A frame taken then photographs the asking rather
        // than the refusal, so the ask is made deliberately and the row is polled until it
        // settles to something that is not *Connecting*.
        if let ask = hittable("Test connection", in: app) ?? control("Test connection", in: app) {
            ask.tap()
        }
        var settledTo = "never read"
        for _ in 0..<25 {
            let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
            settledTo = labels.joined(separator: " | ")
            if labels.contains("Sign-in needed") { break }
            hold(1)
        }
        XCTAssertTrue(
            settledTo.contains("Sign-in needed"),
            """
            The source never reached `Sign-in needed`. The server refuses the stored key \
            with 401, verified by curl, and `reach` maps `KavitaError.keyRejected` to \
            `.unauthorized`, whose status string is `Sign-in needed`. \
            What the screen said instead: \(settledTo)
            """
        )
        return app
    }
}
