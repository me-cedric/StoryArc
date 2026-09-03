import XCTest

/// The player's three sheets, and the compact bar over each destination.
///
/// `PlayerScreenshotTests` photographs the compact bar over the library, the full player at
/// two text sizes, and the sleep timer set and counting. The three sheets the full player
/// leads to — chapters, speed and the sleep-timer picker itself — have no picture, and neither
/// does the compact bar anywhere but on the shelf.
///
/// The walk is `openAnAudiobook(in:)`, in `AudiobookWalk.swift`. It fails by name when the
/// device's shelf has no audiobook rather than photographing an empty one, and it pauses the
/// session — the corpus audiobook is six seconds long, so a run that let it play would see the
/// bar the first time and an empty shelf the second.
@MainActor
final class SweepPlayerTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The chapter list, with the one being played marked by a glyph rather than a colour.
    func testCapturePlayerChapters() throws {
        let app = sweepLaunch()
        try openPlayer(in: app)
        try open("Chapters", landmark: "Chapters", in: app)
        hold(1)
        shutter(app, named: "player-chapters")
    }

    /// The chapter list at the largest accessibility text size.
    func testCapturePlayerChaptersAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openPlayer(in: app)
        try open("Chapters", landmark: "Chapters", in: app)
        hold(1)
        shutter(app, named: "player-chapters-ax5")
    }

    /// The speed sheet: the stops, with the current one ticked.
    ///
    /// The control's own label carries its value — `Speed` with `1×` beside it — so the
    /// button is found by prefix rather than by exact match.
    func testCapturePlayerSpeed() throws {
        let app = sweepLaunch()
        try openPlayer(in: app)
        try openByPrefix("Speed", landmark: "Speed", in: app)
        hold(1)
        shutter(app, named: "player-speed")
    }

    /// The sleep-timer picker, before anything is chosen.
    ///
    /// `sleep-timer-set` and `sleep-timer-counting` photograph the *result*; this is the
    /// sheet, and *End of chapter* — the product decision `design.md` records — is a row only
    /// visible here.
    func testCapturePlayerSleepSheet() throws {
        let app = sweepLaunch()
        try openPlayer(in: app)
        try openByPrefix("Sleep timer", landmark: "Sleep timer", in: app)
        hold(1)
        shutter(app, named: "player-sleep-sheet")
    }

    /// The full player, under this sweep's own appearance control.
    ///
    /// `PlayerScreenshotTests` takes this too, and took it under whatever appearance the
    /// device was left in — which on this device was OLED Dark. The pair a reviewer needs is
    /// light and dark of the same frame.
    func testCapturePlayerFull() throws {
        let app = sweepLaunch()
        try openPlayer(in: app)
        hold(2)
        shutter(app, named: "player-full")
    }

    /// The compact bar over Home, which is the destination whose own hero runs to the bottom.
    func testCaptureCompactPlayerOnHome() throws {
        let app = sweepLaunch()
        try openAnAudiobook(in: app)
        try XCTUnwrap(destination("Home", in: app), "no Home tab").tap()
        hold(2)
        shutter(app, named: "player-compact-on-home")
    }

    /// The compact bar over Search, whose own field sits directly above it.
    func testCaptureCompactPlayerOnSearch() throws {
        let app = sweepLaunch()
        try openAnAudiobook(in: app)
        try XCTUnwrap(destination("Search", in: app), "no Search tab").tap()
        hold(2)
        shutter(app, named: "player-compact-on-search")
    }

    /// The compact bar at the largest accessibility text size, where a title, a chapter and
    /// two controls share one capsule.
    func testCaptureCompactPlayerAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openAnAudiobook(in: app)
        hold(2)
        shutter(app, named: "player-compact-ax5")
    }

    // MARK: - The walk

    /// Starts an audiobook and opens the full player over it.
    private func openPlayer(in app: XCUIApplication) throws {
        try openAnAudiobook(in: app)
        try XCTUnwrap(
            app.buttons["Open the player"].firstMatch,
            "The compact bar offers no way into the player."
        ).tap()
        XCTAssertTrue(
            app.buttons["Chapters"].waitForExistence(timeout: 10),
            "The full player did not open: it offers no chapter control. Buttons: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        hold(1.5)
    }

    /// Opens one of the player's three sheets by exact label.
    private func open(_ control: String, landmark: String, in app: XCUIApplication) throws {
        try XCTUnwrap(hittable(control, in: app), "The player offers no \(control).").tap()
        try assertArrived(landmark, in: app, from: control)
    }

    /// The same, for the two controls whose label carries their current value.
    private func openByPrefix(_ control: String, landmark: String, in app: XCUIApplication) throws {
        let matches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", control))
        _ = matches.firstMatch.waitForExistence(timeout: 5)
        try XCTUnwrap(
            matches.allElementsBoundByIndex.first(where: \.isHittable),
            "The player offers no \(control) control."
        ).tap()
        try assertArrived(landmark, in: app, from: control)
    }

    /// That the sheet is up rather than the player behind it.
    ///
    /// The navigation title, because each of the three sheets has one and the player itself
    /// has none — so this cannot pass on the screen it was opened from.
    private func assertArrived(_ landmark: String, in app: XCUIApplication, from control: String) throws {
        XCTAssertTrue(
            app.navigationBars[landmark].waitForExistence(timeout: 5),
            "\(control) opened no sheet titled \(landmark). Navigation bars: "
                + "\(app.navigationBars.allElementsBoundByIndex.map(\.identifier))"
        )
    }
}
