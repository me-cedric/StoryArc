import XCTest

/// Task 7.5 of `reader-theming-and-page-transitions`: a drag that takes the page over while the
/// previous turn is still settling, photographed.
///
/// `page-transitions` says a new drag during the settle "takes over from where the page is",
/// and `CurlTurnTests` asserts the arithmetic. What a test cannot assert is that nothing
/// *looks* wrong: a page that snaps to its end, or to its start, for one frame. That needs a
/// screen recording, and it needs the second touch to land inside the spring, which lasts about
/// a third of a second.
///
/// `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)` returns only after its
/// finger has lifted, and the next call starts as soon as the test process can build its
/// coordinate. Both coordinates are made before the first press, so the gap is the call itself.
/// Run under `scripts/record-ios-walk.mjs`: the frames are in the recording, and the walk's own
/// shutter is the control, the page after the second finger lifts.
extension CurlWalkTests {

    /// A comic page: dragged past halfway and let go, then caught on its way over and carried
    /// back to where it started.
    func testCaptureCurlInterrupted() throws {
        let app = sweepLaunch()
        try openCurlingComic(in: app)
        interruptedDrag(in: app)
        shutter(app, named: "ios-curl-interrupted-after")
    }
}

extension EpubCurlWalkTests {

    /// The same turn on reflowable text, which is task 8.12's finger-driven curl.
    func testCaptureEpubCurlInterrupted() throws {
        let app = sweepLaunch()
        try openCurlingBook(in: app)
        hold(2)
        interruptedDrag(in: app)
        shutter(app, named: "ios-epub-curl-interrupted-after")
    }
}

/// A forward drag released at 30 percent of the width, which is past halfway, and a second touch
/// put down at once where the first lifted and drawn back to 85 percent. The page must follow
/// the second finger from where the spring had carried it, and not jump.
@MainActor
func interruptedDrag(in app: XCUIApplication) {
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
    let released = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
    let carried = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: released, withVelocity: .default, thenHoldForDuration: 0)
    released.press(forDuration: 0.02, thenDragTo: carried, withVelocity: .slow, thenHoldForDuration: 1.5)
}
