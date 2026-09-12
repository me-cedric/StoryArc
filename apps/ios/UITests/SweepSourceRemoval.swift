import XCTest

/// What removing a library says before it does it.
///
/// Split from `SweepSourceScreens.swift` on 2026-09-12, when that file crossed the 400-line
/// cap. `source-lifecycle` §4.6 is one subject — the two confirmations and what each promises
/// — and the file it left holds the other: the states a source is in.
///
/// **Nothing is confirmed in any walk here.** The shutter fires on the dialog and the walk
/// ends, so the source survives for the walks after it. A walk that removed it would leave
/// every walk in the same run photographing an empty *Your libraries*.
@MainActor
final class SweepSourceRemovalTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
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
        /// The three mock catalogues, injected. It used to be the device's own sources, which
        /// made the frame a matter of whoever used the simulator last — and on 2026-09-12 it
        /// failed outright, because this simulator's registry names none of the two it looked
        /// for. See ``MockCatalogues``.
        case theMockCatalogues
        case aDownload

        /// A catalogue with an id this file chose, so the download below can name it.
        static let catalogueID = "5B1D3E2A-7C4F-4A0B-9E2D-1F6A8C3B7D90"

        var sources: String? {
            switch self {
            case .theMockCatalogues: MockCatalogues.registry
            case .aDownload:
                """
                {"sources":[{"id":"\(Self.catalogueID)","displayName":"Harbour OPDS",\
                "kind":"opdsCatalog","locator":"https://example.invalid/opds"}],"tombstones":[]}
                """
            }
        }

        var downloads: String {
            switch self {
            case .theMockCatalogues: "[]"
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
            case .theMockCatalogues: [MockCatalogues.attic, "StoryArc Test Catalogue", "Attic NAS"]
            case .aDownload: ["Harbour OPDS"]
            }
        }
    }

    private func captureRemovalConfirmation(
        contentSize: String?,
        named name: String,
        holding: Holding = .theMockCatalogues
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

    /// The way in, which is the one thing this shares with the settings sweep.
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
