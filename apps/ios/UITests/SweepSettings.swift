import XCTest

/// Settings, every screen of it.
///
/// `ScreenshotTests` reaches About and the what's-new sheet, and `AppIconCaptureTests` reaches
/// the icon chooser at the foot of Appearance. The other six groups — and the root list they
/// hang off — have never been photographed on iOS, which means the seven-group structure
/// `settings-and-about` specifies has never been looked at as a whole.
///
/// **Every screen proves its own navigation title before the shutter.** The rows are
/// `NavigationLink`s in a `List` and a link that does not fire leaves the root list on screen,
/// which is a plausible-looking picture of any of them.
@MainActor
final class SweepSettingsTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The root: seven groups, each with a summary that says what it currently holds.
    func testCaptureSettingsRoot() throws {
        let app = sweepLaunch()
        try openSettings(in: app)
        hold(0.5)
        shutter(app, named: "settings-root")
    }

    /// The root at the largest accessibility text size, where every row is a title and a
    /// summary and there are seven of them plus a search field.
    func testCaptureSettingsRootAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openSettings(in: app)
        hold(0.5)
        shutter(app, named: "settings-root-ax5")
    }

    /// Appearance: four modes, Natural, the reading-theme link, and the icon chooser below.
    func testCaptureSettingsAppearance() throws {
        let app = sweepLaunch()
        try open("Appearance", in: app)
        shutter(app, named: "settings-appearance")
    }

    /// The same at the largest accessibility text size — four rows each carrying a footnote
    /// of two lines, which is where this screen either scrolls or crowds.
    func testCaptureSettingsAppearanceAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try open("Appearance", in: app)
        shutter(app, named: "settings-appearance-ax5")
    }

    /// Appearance with Natural on, which is the axis that crosses the four modes.
    ///
    /// It has no picture anywhere, and it is the one setting whose effect is a *texture* —
    /// paper grain and warm accents — so a reviewer cannot judge it from the row's own name.
    func testCaptureSettingsAppearanceNatural() throws {
        let app = sweepLaunch(natural: true)
        try open("Appearance", in: app)
        shutter(app, named: "settings-appearance-natural")
    }

    /// Reading: the volume-buttons sentence iOS cannot honour, and the per-scope defaults.
    func testCaptureSettingsReading() throws {
        let app = sweepLaunch()
        try open("Reading", in: app)
        shutter(app, named: "settings-reading")
    }

    /// Reading, scrolled to the matte swatches — the one colour control outside a reader.
    func testCaptureSettingsReadingMatte() throws {
        let app = sweepLaunch()
        try open("Reading", in: app)
        _ = scrollTo(app.staticTexts["Colour behind a comic page"], in: app, swipes: 6)
        hold(0.5)
        shutter(app, named: "settings-reading-matte")
    }

    /// Reading at the largest accessibility text size.
    func testCaptureSettingsReadingAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try open("Reading", in: app)
        shutter(app, named: "settings-reading-ax5")
    }

    /// Privacy: the clear buttons, and the one switch that lets a request leave the device.
    func testCaptureSettingsPrivacy() throws {
        let app = sweepLaunch()
        try open("Privacy", in: app)
        shutter(app, named: "settings-privacy")
    }

    /// Privacy at the largest accessibility text size.
    ///
    /// The cover-lookup row is a label, a provider list and a switch on one line, and the
    /// paragraph under it is the longest sentence on the screen. AGENTS.md section 6 asks for
    /// the largest size as well as the default, and this row is the reason that matters here:
    /// a switch that does not grow beside text that does is where a row breaks.
    /// It scrolls to the row rather than calling ``open(_:in:)``.
    ///
    /// At this text size each settings row is two tall lines, so Privacy is below the fold
    /// and the shared helper's `isHittable` is false before any swipe. Scrolling here rather
    /// than inside the helper keeps a shared walk unchanged, which AGENTS.md section 5 asks
    /// for: a change inside one reaches classes no failure named.
    func testCaptureSettingsPrivacyAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try openSettings(in: app)
        var row: XCUIElement?
        for _ in 0..<8 {
            row = [app.buttons["Privacy"], app.cells["Privacy"], app.staticTexts["Privacy"]]
                .first { $0.exists && $0.isHittable }
            if row != nil { break }
            app.swipeUp()
        }
        try XCTUnwrap(row, "Settings never scrolled to a Privacy row.").tap()
        XCTAssertTrue(
            app.navigationBars["Privacy"].waitForExistence(timeout: 5),
            "Privacy did not open a screen titled Privacy."
        )
        // The cover-lookup row sits between the clear buttons and the diagnostic, so at this
        // text size it is several screens down. A frame of the top of the list would be a
        // picture of the part that did not change.
        //
        // A quarter-screen drag rather than `swipeUp()`: a full swipe carries this list past
        // the row in one gesture, and the first version of this walk photographed the
        // diagnostic at the foot of the screen instead.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        //
        // The stop is read from the row's frame rather than from `isHittable`: a row one
        // pixel inside the bottom edge is hittable, and stopping there photographs the row
        // above it. This stops when the row has reached the upper half of the screen.
        let lookup = app.staticTexts["Look up missing covers"]
        for _ in 0..<20 where !lookup.exists || lookup.frame.minY > app.frame.midY {
            from.press(forDuration: 0.01, thenDragTo: to)
        }
        XCTAssertTrue(lookup.isHittable, "Privacy never scrolled to the cover-lookup row.")
        hold(0.5)
        shutter(app, named: "settings-privacy-ax5")
    }

    /// Privacy with the diagnostic export shown.
    ///
    /// `privacy-and-data`: server names, paths and credentials are removed before it is
    /// shown. A picture of the redacted text is the only proof of that a reviewer can read.
    func testCaptureSettingsPrivacyDiagnostic() throws {
        let app = sweepLaunch()
        try open("Privacy", in: app)
        let show = app.buttons["Show"]
        _ = scrollTo(show, in: app, swipes: 6)
        guard show.exists, show.isHittable else {
            throw XCTSkip("Privacy showed no diagnostic control on this build.")
        }
        show.tap()
        hold(1)
        shutter(app, named: "settings-privacy-diagnostic")
    }

    /// Downloads and storage: the limit, the Wi-Fi rule, and what is on the device.
    func testCaptureSettingsDownloads() throws {
        let app = sweepLaunch()
        try open("Downloads and storage", in: app)
        shutter(app, named: "settings-downloads")
    }

    /// Language: the four StoryArc speaks, and System.
    func testCaptureSettingsLanguage() throws {
        let app = sweepLaunch()
        try open("Language", in: app)
        shutter(app, named: "settings-language")
    }

    /// The app in French, so the language override is shown doing something rather than
    /// merely offered.
    ///
    /// `localization` lets a reader choose the app's language without touching the device's,
    /// and a list of four language names proves nothing about whether the app is translated.
    func testCaptureSettingsLanguageFrench() throws {
        let app = sweepLaunch(language: "fr")
        try XCTUnwrap(control("Réglages", in: app) ?? control("Settings", in: app)).tap()
        hold(1)
        shutter(app, named: "settings-root-french")
    }

    /// About, under this sweep's own appearance control.
    func testCaptureSettingsAbout() throws {
        let app = sweepLaunch()
        try open("About", in: app)
        hold(0.5)
        shutter(app, named: "settings-about")
    }

    /// Resetting, confirmed — the one place Settings names its own blast radius.
    func testCaptureSettingsResetConfirmation() throws {
        let app = sweepLaunch()
        try openSettings(in: app)
        let reset = app.buttons["Reset settings"]
        _ = scrollTo(reset, in: app, swipes: 4)
        try XCTUnwrap(hittable("Reset settings", in: app), "Settings offers no reset.").tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Appearance, reading preferences")
            ).firstMatch.waitForExistence(timeout: 5),
            "Reset asked for no confirmation naming what survives."
        )
        hold(0.5)
        shutter(app, named: "settings-reset-confirm")
    }

    // MARK: - The walk

    /// Home → Settings → one group, with that group's own navigation title on screen.
    private func open(_ group: String, in app: XCUIApplication) throws {
        try openSettings(in: app)
        try XCTUnwrap(control(group, in: app), "Settings has no \(group) row.").tap()
        XCTAssertTrue(
            app.navigationBars[group].waitForExistence(timeout: 5),
            "\(group) did not open a screen titled \(group). Navigation bars: "
                + "\(app.navigationBars.allElementsBoundByIndex.map(\.identifier))"
        )
        hold(0.5)
    }
}
