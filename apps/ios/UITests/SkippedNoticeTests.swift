import XCTest

/// That the notice outlives the six seconds the toast it replaced had.
///
/// `library-browsing`: the notice "stays until the reader dismisses it or resolves it". What
/// stood here was `ScanSummary`, a Liquid Glass capsule with `dwell = .seconds(6)` and an
/// `@State private var isShowing` that a `Task.sleep` cleared. **A test that only checked the
/// notice appears would pass against that**, which is the whole reason this walk exists on a
/// device rather than only as a rule in the host suite.
///
/// Two guards run in the host suite and neither can settle this one:
/// `SkippedPublicationsTests` asserts the notice is a pure function of the model's value, and
/// `SkippedNoticeTimerTests` asserts the view contains no sleep, no duration and no
/// visibility state. Both are structural. This is the only one that waits.
///
/// Android's `SkippedNoticeTest` asserts the same claim in its unit suite, because Compose's
/// test clock can be advanced past seven seconds; XCTest has no equivalent for a SwiftUI
/// view, so iOS pays for it with a real wait on a real simulator.
@MainActor
final class SkippedNoticeTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Long enough to prove the point with a margin, short enough not to be furniture in a
    /// suite. The dwell was six.
    private static let pastTheDwell: TimeInterval = 9

    func testTheNoticeSurvivesLongerThanTheOldSixSeconds() throws {
        let app = launch()
        try XCTUnwrap(destination("Library", in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)

        // The named control is what identifies the notice: the sentence itself is localised
        // and interpolates a filename, and the control's label is one string in the
        // catalogue.
        let wayIn = app.buttons["What couldn’t be opened"].firstMatch
        guard wayIn.waitForExistence(timeout: 20) else {
            throw XCTSkip(
                "No skipped-publications notice on this device. Run "
                    + "`node scripts/corpus.mjs --simulator` first — the library has to hold "
                    + "something the app cannot open for this to have a subject."
            )
        }

        wait(Self.pastTheDwell)

        XCTAssertTrue(
            wayIn.exists,
            "The notice went away on its own after \(Self.pastTheDwell)s. That is the toast."
        )
    }

    /// Parks on an expectation rather than sleeping: `Thread.sleep` blocks the main actor and
    /// starves the run loop, so a view that removes itself on a timer would never get the
    /// chance to and the test would pass against the defect.
    private func wait(_ seconds: TimeInterval) {
        let waited = XCTestExpectation(description: "waited \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { waited.fulfill() }
        wait(for: [waited], timeout: seconds + 5)
    }
}
