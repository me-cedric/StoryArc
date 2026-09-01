import XCTest

/// The app icon, photographed where it is actually seen.
///
/// `brand-identity-and-app-icons` task 6.1: "every face rendered and photographed on a device
/// home screen … the icon is the deliverable, so a screenshot of the chooser is not sufficient
/// on its own". A chooser screenshot shows what the app draws in a list; only the home screen
/// shows what the *system* draws, at the size and with the mask a reader sees — and the mask is
/// the part no in-app tile can prove.
///
/// **One test per face, not one loop over five.** The first version walked all five and then
/// reset, and it was killed at fourteen minutes with a `signal kill` and no message: six walks
/// in one test is six chances to wedge, and a hang in the sixth throws away the five
/// screenshots the first five had already taken. Each test here is one walk, and the harness
/// runs the class.
///
/// Its own file rather than more of `ScreenshotTests`, which is at the length the linter warns
/// at. `SkippedNoticeCapture.swift` split off for the same reason. Drive it with:
/// ```
/// pnpm capture:ios --out <dir> --only AppIconCaptureTests
/// ```
@MainActor
final class AppIconCaptureTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Every face, on a home screen

    func testCaptureHomeAInk() throws { try captureHome("Ink") }
    func testCaptureHomeBPaper() throws { try captureHome("Paper") }
    func testCaptureHomeCBloom() throws { try captureHome("Bloom") }
    func testCaptureHomeDArc() throws { try captureHome("Arc") }
    func testCaptureHomeEMono() throws { try captureHome("Mono") }

    /// Puts the default back, and captures nothing.
    ///
    /// The chosen icon is *platform* state — `alternateIconName` survives the app being killed,
    /// which is the whole reason the chooser has nothing of its own to store — so a run that
    /// ended on Mono would leave Mono on for the next person's captures too. Named to sort
    /// last, because XCTest runs a class's tests in alphabetical order and this one has to.
    func testZZRestoreTheDefaultIcon() throws {
        _ = try chooseFace("Ink")
    }

    // MARK: - The chooser

    /// The chooser itself, at the default text size.
    func testCaptureAppIconChooser() throws {
        let app = launch()
        try openChooser(app)
        attach(app.screenshot(), named: "app-icon-chooser")
    }

    /// And at the largest accessibility size.
    ///
    /// `settings-and-about`: "every option's name is readable in full and its tile is still
    /// large enough to tell the faces apart, the list scrolling if it must". Three claims a
    /// picture can settle and no unit test can: the tile is a fixed 60 points precisely so the
    /// name beside it keeps the width it needs, and whether that was the right call is visible
    /// here or nowhere.
    func testCaptureAppIconChooserAtLargestText() throws {
        let app = launch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openChooser(app)
        attach(app.screenshot(), named: "app-icon-chooser-ax5")
    }

    // MARK: - The walk

    private func captureHome(_ face: String) throws {
        _ = try chooseFace(face)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        _ = springboard.wait(for: .runningForeground, timeout: 15)
        // SpringBoard redraws the icon when the change lands, and it is not instant. Not a
        // guess at a race — it is the settle the crossfade takes, and the alternative is
        // photographing the previous icon halfway through it.
        settle(1.5)
        attach(XCUIScreen.main.screenshot(), named: "home-\(face.lowercased())")
    }

    /// Home → Settings → Appearance, scrolled until the chooser is on screen.
    private func openChooser(_ app: XCUIApplication) throws {
        try XCTUnwrap(control("Settings", in: app), "Home has no way into Settings.").tap()
        try XCTUnwrap(control("Appearance", in: app), "Settings has no Appearance row.").tap()
        // The section is below four appearance rows and three switches, so it is off screen at
        // any text size on a phone. Scrolling to a known row is what makes the capture show
        // the thing it is named after rather than the top of a list.
        let mono = row("Mono", in: app)
        for _ in 0..<8 where !mono.waitForExistence(timeout: 2) || !mono.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(mono.exists, "Appearance never revealed the icon chooser.")
    }

    /// Picks a face, answers the system alert, and waits for the chooser to mark it.
    ///
    /// **The alert is not suppressed** — design.md is explicit that suppressing it rides on a
    /// private delegate method — so a walk that changes the icon has to answer it. That it is
    /// there at all is a fact about the platform this walk happens to prove.
    ///
    /// Waiting for the *mark* rather than for a duration is what makes the home-screen shot
    /// trustworthy: the chooser only marks a row once `setAlternateIconName` has confirmed, so
    /// a mark means the platform has agreed and a timeout means it has not.
    private func chooseFace(_ face: String) throws -> XCUIApplication {
        let app = launch()
        try openChooser(app)
        let wanted = row(face, in: app)
        if wanted.isSelected { return app }
        wanted.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 8) {
            alert.buttons.allElementsBoundByIndex.last?.tap()
        }

        for _ in 0..<20 where !row(face, in: app).isSelected { settle(0.5) }
        XCTAssertTrue(
            row(face, in: app).isSelected,
            "\(face) was never marked as the icon in use, so the platform did not confirm it."
        )
        return app
    }

    // MARK: - Finding things

    /// One row of the icon chooser.
    ///
    /// `BEGINSWITH` because the row is one accessibility element carrying everything in it —
    /// the default's row reads "Ink, Default" — which is the shape `settings-and-about` asks
    /// for and the shape an exact-label lookup cannot find.
    private func row(_ face: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", face)).firstMatch
    }

    // `control(_:in:)` and `launch(contentSize:language:)` are `AuditWalk.swift`'s, shared by
    // every suite that walks this app — and they cannot be redeclared here even privately:
    // `XCTestCase` is an Objective-C class, so an extension's methods are dynamically
    // dispatched, and a same-named method in a subclass is an override the compiler refuses
    // without the keyword. `settle` and `attach` are per-class by convention instead.

    private func settle(_ seconds: TimeInterval) {
        let settled = XCTestExpectation(description: "waited \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { settled.fulfill() }
        wait(for: [settled], timeout: seconds + 3)
    }

    /// `.keepAlways`: an attachment on a passing test is deleted by default, and a capture
    /// suite whose every test passes would produce nothing at all.
    private func attach(_ shot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
