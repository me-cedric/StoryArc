import XCTest

/// The A to Z rail, photographed at rest, under a held finger and in a short window.
///
/// Task 24.6 of `close-the-audited-gaps`. Default text size only; the appearance is the
/// simulator's and `capture-ios.mjs --appearance` sets it.
///
/// **The held frame is taken from another thread.** A UI-test gesture blocks the test's own
/// thread until the finger lifts, so the picture of a finger that is still down has to be
/// asked for while the gesture runs.
@MainActor
final class SweepRailTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Every letter drawn on the trailing edge, nothing chosen.
    func testCaptureRailAtRest() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        _ = try theRail(in: app)
        hold(1.5)
        shutter(app, named: "library-rail-rest")
    }

    /// A finger held part-way down the rail: the bubble with the letter beside the finger.
    func testCaptureRailDuringADrag() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        let rail = try theRail(in: app)
        hold(1)

        let box = ShotBox()
        for delay in [2.0, 3.0] {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                box.add(XCUIScreen.main.screenshot())
            }
        }
        rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).press(
            forDuration: 0.2,
            thenDragTo: rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
            withVelocity: .slow,
            thenHoldForDuration: 4
        )
        let shots = box.shots
        XCTAssertFalse(shots.isEmpty, "No picture was taken while the finger was down.")
        for (index, shot) in shots.enumerated() {
            shutter(shot: shot, named: "library-rail-drag-\(index)")
        }
    }

    /// A phone on its side: the shelf is short, so the drawn letters thin out.
    func testCaptureRailInLandscape() throws {
        let app = sweepLaunch()
        try showTheShelf(in: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        _ = try theRail(in: app)
        hold(4)
        // The raw screen, which arrives in the device's portrait buffer with the picture turned
        // a quarter circle. `app.screenshot()` of a rotated app is not usable: it draws the
        // app small and sideways. The README records the turn applied to the file.
        shutter(shot: XCUIScreen.main.screenshot(), named: "library-rail-landscape")
    }

    /// The same two frames on an iPad, in landscape, where the shelf sits beside a sidebar.
    /// Skipped on a phone by `landscape()`. Run with `--device` pointed at an iPad.
    func testCaptureIpadRailAtRest() throws {
        let app = try landscape()
        try go(to: "Library", in: app)
        _ = try theRail(in: app)
        hold(2)
        shutter(app, named: "ipad-library-rail-rest")
    }

    func testCaptureIpadRailDuringADrag() throws {
        let app = try landscape()
        try go(to: "Library", in: app)
        let rail = try theRail(in: app)
        hold(1)
        try dragAndHold(rail, named: "ipad-library-rail-drag")
    }

    private func dragAndHold(_ rail: XCUIElement, named name: String) throws {
        let box = ShotBox()
        for delay in [2.0, 3.0] {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                box.add(XCUIScreen.main.screenshot())
            }
        }
        rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).press(
            forDuration: 0.2,
            thenDragTo: rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
            withVelocity: .slow,
            thenHoldForDuration: 4
        )
        let shots = box.shots
        XCTAssertFalse(shots.isEmpty, "No picture was taken while the finger was down.")
        for (index, shot) in shots.enumerated() {
            shutter(shot: shot, named: "\(name)-\(index)")
        }
    }

    private func theRail(in app: XCUIApplication) throws -> XCUIElement {
        let rail = app.descendants(matching: .any).matching(identifier: "library.rail").firstMatch
        try XCTSkipUnless(rail.waitForExistence(timeout: 10), "This corpus draws no index.")
        return rail
    }
}

/// Pictures taken on a queue other than the test's own.
private final class ShotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [XCUIScreenshot] = []

    func add(_ shot: XCUIScreenshot) {
        lock.lock()
        held.append(shot)
        lock.unlock()
    }

    var shots: [XCUIScreenshot] {
        lock.lock()
        defer { lock.unlock() }
        return held
    }
}
