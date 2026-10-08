import XCTest

/// The downloads queue: each transfer's actions are one menu, and so are the whole queue's.
///
/// Task 24.3 of `close-the-audited-gaps`. A row carried up to four small buttons side by side,
/// each 28 pt tall and 8 pt from the next. `SweepDownloadsTests` injects the three transfers
/// this reads, so no server is needed and nothing is written to the standard domain.
extension AccessibilityAuditTests {

    func testTheQueueOffersEachTransfersActionsAsOneMenu() throws {
        let app = sweepLaunch(downloads: SweepDownloadsTests.queue)
        try XCTUnwrap(destination("Downloads", in: app)).tap()
        XCTAssertTrue(
            app.staticTexts["Coming down now"].waitForExistence(timeout: 10),
            "No transfer queue on this screen. The injected download record was not read."
        )

        for loose in ["Pause", "Stop", "Retry", "Remove download", "Pause all", "Cancel all"] {
            XCTAssertFalse(app.buttons[loose].exists, "\(loose) is a button of its own again, not a row of a menu.")
        }
        try audit(app, named: "Downloads queue", types: .hitRegion)

        let all = app.buttons["All downloads"]
        XCTAssertTrue(all.exists, "The queue has no menu for every transfer at once.")
        XCTAssertGreaterThanOrEqual(all.frame.height, 44, "All downloads is shorter than 44 pt.")

        let failed = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Actions for' AND label CONTAINS 'The Peregrine'")
        ).firstMatch
        XCTAssertTrue(failed.waitForExistence(timeout: 5), "The failed transfer has no actions menu.")
        XCTAssertGreaterThanOrEqual(failed.frame.width, 44, "The actions button is narrower than 44 pt.")
        XCTAssertGreaterThanOrEqual(failed.frame.height, 44, "The actions button is shorter than 44 pt.")

        failed.tap()
        let retry = app.buttons["Retry"]
        let remove = app.buttons["Remove download"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "The failed transfer's menu offers no Retry.")
        XCTAssertTrue(remove.exists, "The failed transfer's menu offers no Remove download.")
        XCTAssertGreaterThan(remove.frame.minY, retry.frame.minY, "Remove download is not the last row.")
        XCTAssertFalse(app.buttons["Stop"].exists, "A failed transfer is offered a Stop it cannot honour.")
    }
}
