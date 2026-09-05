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

    /// The removal confirmation, raised from the source detail screen's *Remove* row.
    ///
    /// `source-lifecycle` §4.6. Both strings have to be legible: the count of titles the
    /// removal affects, and the sentence about the thirty days a reader has to change their
    /// mind. A confirmation dialog is where truncation costs a reader their library, which is
    /// why the largest-text pair is not optional for this one.
    ///
    /// Nothing is confirmed. The shutter fires on the dialog and the walk ends, so the source
    /// survives for the next walk in the same run — a walk that removed it would leave every
    /// walk after it photographing an empty *Your libraries*.
    func testCaptureSourceRemovalConfirmation() throws {
        try captureRemovalConfirmation(contentSize: nil, named: "settings-source-remove")
    }

    /// The same dialog at the largest accessibility text size.
    func testCaptureSourceRemovalConfirmationAtLargestText() throws {
        try captureRemovalConfirmation(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            named: "settings-source-remove-ax5"
        )
    }

    /// The confirmation for a source that holds a download, which is the sentence that names
    /// what removal deletes — and the one the device's own sources can never show, because
    /// none of them has fetched anything.
    ///
    /// The registry and the record are injected together: a download belongs to a source by
    /// `sourceID`, so the walk registers a catalogue whose id it chose and hands the store one
    /// finished download carrying that id. `SourceDiagnosis` then counts it exactly as it
    /// counts a real one, and the dialog reads *This removes 0 titles and 1 download (2.1 MB)*.
    /// Zero titles, because the injected catalogue has no publications on this device; the
    /// figure that matters here is the other one.
    func testCaptureSourceRemovalConfirmationWithDownloads() throws {
        try captureRemovalConfirmation(
            contentSize: nil,
            named: "settings-source-remove-downloads",
            holding: .aDownload
        )
    }

    /// The same sentence at the largest accessibility text size, where a confirmation holds
    /// about seven short lines and the size is the last thing in it. If the frame cuts the
    /// figure, the sentence is too long, and this is the walk that would show it.
    func testCaptureSourceRemovalConfirmationWithDownloadsAtLargestText() throws {
        try captureRemovalConfirmation(
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL",
            named: "settings-source-remove-downloads-ax5",
            holding: .aDownload
        )
    }

    /// What the removal walk finds on the device: its own sources, or an injected one.
    private enum Holding {
        case theDeviceSources
        case aDownload

        /// A catalogue with an id this file chose, so the download below can name it.
        static let catalogueID = "5B1D3E2A-7C4F-4A0B-9E2D-1F6A8C3B7D90"

        var sources: String? {
            switch self {
            case .theDeviceSources: nil
            case .aDownload:
                """
                {"sources":[{"id":"\(Self.catalogueID)","displayName":"Harbour OPDS",\
                "kind":"opdsCatalog","locator":"https://example.invalid/opds"}],"tombstones":[]}
                """
            }
        }

        var downloads: String {
            switch self {
            case .theDeviceSources: "[]"
            case .aDownload:
                """
                [{"id":"sweep-landed","sourceID":"\(Self.catalogueID)","title":"Harbour Lights 03",\
                "remote":"https://example.invalid/hl03.epub","mediaType":"application/epub+zip",\
                "expectedBytes":2100000,"downloadedBytes":2100000,"isFinished":true,\
                "attempts":1,"verificationFailures":0}]
                """
            }
        }

        var sourceNames: [String] {
            switch self {
            case .theDeviceSources: ["StoryArc Test Catalogue", "Attic NAS"]
            case .aDownload: ["Harbour OPDS"]
            }
        }
    }

    private func captureRemovalConfirmation(
        contentSize: String?,
        named name: String,
        holding: Holding = .theDeviceSources
    ) throws {
        let app = sweepLaunch(contentSize: contentSize, downloads: holding.downloads, sources: holding.sources)
        try open("Your libraries", in: app)
        let source = try XCTUnwrap(
            holding.sourceNames.lazy.compactMap { self.control($0, in: app) }.first,
            "Your libraries lists no catalogue. Cells: "
                + "\(app.cells.allElementsBoundByIndex.prefix(10).map(\.label))"
        )
        source.tap()
        // Scrolled to first, because at the accessibility sizes it is below the fold — five
        // fields that each became two lines put the actions off the bottom of the screen, and
        // the first version of this walk failed there with "offers no Remove row" while
        // passing at the default size. `testCaptureSettingsResetConfirmation` scrolls for the
        // same reason.
        _ = scrollTo(app.buttons["Remove"], in: app, swipes: 4)
        let remove = try XCTUnwrap(
            hittable("Remove", in: app, timeout: 8),
            "The source page offers no Remove row, even after scrolling."
        )
        remove.tap()
        // The body opens with what the removal does — *This removes* — in both of its states,
        // and that is what is waited for rather than the dialog's own element, because what
        // the platform calls a confirmation has changed between releases and the sentence is
        // what the task is about. Not the thirty days: since 2026-09-05 they are the footer on
        // the screen beneath, which `staticTexts` would find with the dialog open or closed —
        // so a wait on them proved nothing about the dialog, and passed here for that reason.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "This removes")
            ).firstMatch.waitForExistence(timeout: 5),
            "Remove raised no confirmation stating what it removes. On screen: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label))"
        )
        if case .aDownload = holding {
            // The branch, not merely the dialog: a body that stayed on the titles-only sentence
            // would pass the wait above and photograph the wrong claim.
            XCTAssertTrue(
                app.staticTexts.matching(
                    NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "This removes", "download")
                ).firstMatch.exists,
                "The source holds a download and the confirmation did not name it. On screen: "
                    + "\(app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label))"
            )
        }
        hold(0.5)
        shutter(app, named: name)

        // **The second frame is what turns "clipped" into "unreachable".** At the accessibility
        // sizes the message outgrows the confirmation and stops mid-sentence — the first frame
        // ends at *"No files"* — and a still cannot tell a scrollable clip from a hard
        // truncation. So the walk swipes and shoots again: the two frames are **identical**,
        // which is the finding. The retention sentence cannot be reached by scrolling.
        //
        // The assertion above still passes at this size, and that is worth knowing rather than
        // hiding: `staticTexts` reads the accessibility tree, where the whole message exists as
        // one label. VoiceOver reads it in full. A sighted reader at `AccessibilityXXXL` cannot
        // see it at all. A test that asserted only existence would have called this screen
        // correct.
        guard contentSize != nil else { return }
        app.swipeUp(velocity: .slow)
        hold(0.5)
        shutter(app, named: "\(name)-scrolled")
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
