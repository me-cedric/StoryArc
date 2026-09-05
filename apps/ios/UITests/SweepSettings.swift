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

    /// Privacy: the group with nothing to opt out of, which is the point of it.
    func testCaptureSettingsPrivacy() throws {
        let app = sweepLaunch()
        try open("Privacy", in: app)
        shutter(app, named: "settings-privacy")
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

    /// Your libraries: the five sources this device carries, with their states.
    func testCaptureSettingsSources() throws {
        let app = sweepLaunch()
        try open("Your libraries", in: app)
        hold(1)
        shutter(app, named: "settings-sources")
    }

    /// One source's page: what it is, when it last answered, and what can be done to it.
    ///
    /// An OPDS catalogue rather than a folder, because a folder's page has no sign-in, no
    /// last-sync and no error to state — three of the five rows this screen exists for.
    func testCaptureSettingsSourceDetail() throws {
        let app = sweepLaunch()
        try open("Your libraries", in: app)
        let source = try XCTUnwrap(
            control("StoryArc Test Catalogue", in: app) ?? control("Attic NAS", in: app),
            "Your libraries lists no catalogue. Cells: "
                + "\(app.cells.allElementsBoundByIndex.prefix(10).map(\.label))"
        )
        source.tap()
        XCTAssertTrue(
            app.staticTexts["Status"].waitForExistence(timeout: 5),
            "The source did not open a page stating its status."
        )
        hold(1)
        shutter(app, named: "settings-source-detail")
    }

    /// The same page at the largest accessibility text size.
    ///
    /// `source-lifecycle` §4.1 asks for this screen at both text sizes and there has never been
    /// a walk for the larger one. It is the screen with the most to lose: five rows that are
    /// each a label on the left and a value on the right, and two of the values are a date and
    /// a sentence — *No answer since Sep 5, 2026 at 15:02* already wraps to two lines at the
    /// default size, so what it does at `AccessibilityXXXL` is the question.
    ///
    /// A method rather than a flag, following `testCaptureSettingsRootAtLargestText`: the
    /// content size is a launch argument, so it cannot be varied within a run.
    func testCaptureSettingsSourceDetailAtLargestText() throws {
        let app = sweepLaunch(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        try open("Your libraries", in: app)
        let source = try XCTUnwrap(
            control("StoryArc Test Catalogue", in: app) ?? control("Attic NAS", in: app),
            "Your libraries lists no catalogue. Cells: "
                + "\(app.cells.allElementsBoundByIndex.prefix(10).map(\.label))"
        )
        source.tap()
        XCTAssertTrue(
            app.staticTexts["Status"].waitForExistence(timeout: 5),
            "The source did not open a page stating its status."
        )
        hold(1)
        shutter(app, named: "settings-source-detail-ax5")
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
