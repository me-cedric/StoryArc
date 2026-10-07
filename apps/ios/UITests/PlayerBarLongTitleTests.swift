import XCTest

/// The shelf with the compact bar over a title too long for it, light and dark, at the default
/// text size and at the largest.
///
/// Task 8.4. The bar cuts a long title at the tail on purpose, because the height of
/// `tabViewBottomAccessory` is the system's, and `audio-playback` asks instead that the cut
/// be marked, that the text be announced in full, and that the player it opens show it in
/// full. A picture shows the first clause and the audit shows what the platform finds wrong
/// with it; the announcement is asserted here as a value.
///
/// **It needs `Across the Minch to the Shiants…` on the Downloads shelf**, which
/// `scripts/seed-simulator.mjs` puts there beside `Sea Room`. The light and dark runs are the
/// `--appearance` flag of the capture script:
/// `node scripts/capture-ios.mjs --out <dir> --only PlayerBarLongTitleTests --appearance light`,
/// then `dark`. The audit reports and does not fail, for the reason `AuditWalk.reportOnly`
/// gives; what can fail here is failing to reach the bar, or the bar announcing less than the
/// whole title.
@MainActor
final class PlayerBarLongTitleTests: XCTestCase {

    private static let title = "Across the Minch to the Shiants and Bird Island on the Long Road Home"

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTheBarOverALongTitleAtTheDefaultSize() throws {
        try photographTheBar(contentSize: nil, named: "compact-bar-long-title", audit: "Compact bar, long title")
    }

    func testTheBarOverALongTitleAtTheLargestSize() throws {
        try photographTheBar(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            named: "compact-bar-long-title-ax5",
            audit: "Compact bar, long title (AccessibilityXXXL)"
        )
    }

    private func photographTheBar(contentSize: String?, named name: String, audit: String) throws {
        let app = launch(contentSize: contentSize)
        try openAnAudiobook(in: app, titled: Self.title)

        let wayIn = app.buttons["Open the player"].firstMatch
        XCTAssertTrue(wayIn.exists, "The bar offered no way into the player.")
        // Whole, however the row cuts it: the announcement is the title the bar cannot show.
        let value = wayIn.value as? String ?? ""
        XCTAssertTrue(
            value.contains(Self.title),
            "The bar announces \"\(value)\", which leaves out the end of the title the row cuts."
        )

        // The walk ends on the book's page, with the bar over it. The frame this task is owed is
        // the shelf, so go back to it. At the largest size the walk scrolls the shelf to find
        // the cover, which minimises the tab bar, so a swipe down brings the tabs back first.
        if destination("Library", in: app) == nil { app.swipeDown() }
        try XCTUnwrap(destination("Library", in: app), "The shell offers no Library tab.").tap()
        for _ in 0..<3 where !app.navigationBars["Library"].exists {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.waitForExistence(timeout: 3) else { break }
            back.tap()
            _ = app.navigationBars["Library"].waitForExistence(timeout: 2)
        }
        XCTAssertTrue(
            app.navigationBars["Library"].exists,
            "The walk never got back to the shelf. Bars: "
                + "\(app.navigationBars.allElementsBoundByIndex.map(\.identifier))"
        )
        XCTAssertTrue(wayIn.exists, "The bar went when the shelf came back.")

        let settled = XCTestExpectation(description: "the bar has settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 4)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        try reportOnly(app, named: audit)
    }
}
