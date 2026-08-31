import XCTest

/// Photographs a screen, so that `AGENTS.md` section 6's visual proof is repeatable.
///
/// Android has `pnpm capture:android`, which walks to a named screen, sets the text size and
/// the appearance, photographs it, and puts the device back. iOS had `xcrun simctl io booted
/// screenshot`, which photographs whatever happens to be in front of it — so every iOS proof
/// this project has taken involved a person driving the simulator by hand, and the one time
/// that was automated with synthetic clicks the coordinates missed the tab bar and produced
/// a picture of Home labelled *Downloads*.
///
/// A UI test already knows how to reach a screen: `AuditWalk.swift` owns that, and the audit
/// suite has been walking these same destinations for a day. Reusing it means the capture
/// cannot drift away from the walk that the audit and the crash checks use.
///
/// The screenshots come out of the result bundle:
/// ```
/// xcodebuild test -project apps/ios/StoryArc.xcodeproj -scheme StoryArc \
///   -destination 'platform=iOS Simulator,name=StoryArc-iPhone17Pro' \
///   -only-testing:StoryArcUITests/ScreenshotTests -resultBundlePath /tmp/shots.xcresult
/// xcrun xcresulttool export attachments --path /tmp/shots.xcresult --output-path /tmp/shots
/// ```
///
/// `.keepAlways` matters: an attachment on a passing test is deleted by default, and a
/// capture suite whose every test passes would produce nothing at all.
@MainActor
final class ScreenshotTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCaptureDownloads() throws {
        let app = launch()
        try XCTUnwrap(destination("Downloads", in: app)).tap()
        // The shelf, not the tab: tapping a tab is instant and decoding covers is not, and a
        // screenshot taken between the two shows an empty grid on every build alike — which
        // would make a before and an after identical for a reason that has nothing to do
        // with the change.
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "downloads")
    }

    func testCaptureHome() throws {
        let app = launch()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "home")
    }

    func testCaptureLibrary() throws {
        let app = launch()
        try XCTUnwrap(destination("Library", in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        attach(app.screenshot(), named: "library")
    }

    private func attach(_ shot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
