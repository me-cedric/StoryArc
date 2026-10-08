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

    /// `one-vocabulary-in-four-languages` 1.8. With the interface in French, each entry in the
    /// list behind the notice is one element whose label holds the file's name and the French
    /// reason together, and the notice counts in French.
    ///
    /// What a host unit test cannot say: `SkippedNoticeAnnouncementTests` asserts the reason's
    /// key sits in the merged element, but the host answers with the key and no language. This
    /// reads the label the system hands VoiceOver, on a simulator whose app language is French.
    /// A person with VoiceOver still confirms the speech.
    func testFrenchEntryIsOneStopWithTheFrenchReason() throws {
        let app = try openTheList(language: "fr", tab: "Bibliothèque", control: "Ce qui n’a pas pu être ouvert")

        assertOneStop(
            name: "Locked Vault.cbz", reason: "l’archive est protégée par un mot de passe",
            leaked: "password protected", in: app
        )
        assertOneStop(
            name: "Sealed Archive.cb7", reason: "StoryArc ne lit pas le format CB7",
            leaked: "is not a format StoryArc reads", in: app
        )
    }

    /// The control: the same two entries with the interface in English.
    func testEnglishEntryIsOneStopWithTheEnglishReason() throws {
        let app = try openTheList(language: "en", tab: "Library", control: "What couldn’t be opened")

        assertOneStop(
            name: "Locked Vault.cbz", reason: "the archive is password protected",
            leaked: "mot de passe", in: app
        )
        assertOneStop(
            name: "Sealed Archive.cb7", reason: "CB7 is not a format StoryArc reads",
            leaked: "ne lit pas le format", in: app
        )
    }

    /// The notice itself counts in French, as one element.
    func testFrenchNoticeCountsInFrench() throws {
        let app = launch(language: "fr")
        try XCTUnwrap(destination("Bibliothèque", in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        try requireTheNotice(in: app, control: "Ce qui n’a pas pu être ouvert")

        let counted = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "n’ont pas pu être ouverts"))
        XCTAssertGreaterThanOrEqual(counted.count, 1, "the notice does not count in French")
        let english = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "couldn’t be opened"))
        XCTAssertEqual(english.count, 0, "English inside a French notice")
    }

    private func openTheList(language: String, tab: String, control: String) throws -> XCUIApplication {
        let app = launch(language: language)
        try XCTUnwrap(destination(tab, in: app)).tap()
        _ = app.scrollViews.firstMatch.waitForExistence(timeout: 10)
        try requireTheNotice(in: app, control: control).tap()
        _ = app.collectionViews.firstMatch.waitForExistence(timeout: 5)
        return app
    }

    @discardableResult
    private func requireTheNotice(in app: XCUIApplication, control: String) throws -> XCUIElement {
        let wayIn = app.buttons[control].firstMatch
        guard wayIn.waitForExistence(timeout: 20) else {
            throw XCTSkip(
                "No skipped-publications notice on this device. Run "
                    + "`node scripts/corpus.mjs --simulator <udid>` first."
            )
        }
        return wayIn
    }

    private func assertOneStop(
        name: String, reason: String, leaked: String, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        // Exactly one element carries the name and the reason together. Its children stay in
        // the snapshot and are not stops of their own: `.combine` makes the parent the element
        // VoiceOver visits, and `SkippedNoticeAnnouncementTests` asserts that structure.
        let both = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", name, reason)
        )
        // The list can still be drawing after a slow launch; counting at once read zero.
        _ = both.firstMatch.waitForExistence(timeout: 10)
        XCTAssertEqual(
            both.count, 1, "not one element says \(name) and “\(reason)” together", file: file, line: line
        )
        let wrongLanguage = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", leaked)
        )
        XCTAssertEqual(wrongLanguage.count, 0, "“\(leaked)” is spoken in this language", file: file, line: line)
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
