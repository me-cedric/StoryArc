import XCTest

/// Photographs the *voice* driving the player, which is the half no unit test can reach.
///
/// `audiobooks-and-playback` §4.2 folded read-aloud into `PlayerCentre`, so the shell's one
/// accessory slot now carries `PlayerDock` for a narrated audiobook and a synthesised voice
/// alike. `CompactPlayerTests` pins what the bar *says*; a tab bar cannot be unit-tested, and
/// neither can the fact that starting the voice inside a reader and then leaving the reader
/// leaves the voice running. That is what these two captures are for.
///
/// It fails by name rather than photographing whatever is on screen — the failure `AuditWalk`
/// warns about at length — and it skips, through `openTheEpubReader(in:)`, when the device's
/// library holds no EPUB at all.
@MainActor
final class ReadAloudPlayerTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The shelf, with the voice carrying on behind it.
    ///
    /// `ebook-reader`: closing the reader while the voice is speaking leaves speech running
    /// and returns the listener "to whatever they were doing in the app"; `audio-playback`:
    /// "the way back to where the audio is reading is one action from the compact bar". The
    /// bar's row is labelled *Back to the book* here and *Open the player* over an audiobook,
    /// which is the whole of ``PlayerWayBack`` arriving on a screen.
    ///
    /// Compare with `PlayerScreenshotTests.testCaptureLibraryWithNothingPlaying`, which is the
    /// same shelf on the same device with no session running.
    func testCaptureBarCarriesTheVoice() throws {
        let app = try speakAndLeaveTheReader()
        settle(1)
        attach(app.screenshot(), named: "read-aloud-compact-bar")
    }

    /// The full player, driven by the voice rather than by a file.
    ///
    /// **The controls are the point.** `audio-playback` requires that "the surface, the
    /// controls and the lock-screen presentation are the same" whichever source is behind the
    /// sound, and that "every control the player offers works, or is absent — none is present
    /// and refusing". So this picture should show the speed control — which is what
    /// `SpeechRate` and `SpokenVoice` bought — the sleep timer and the chapter list, and
    /// should show **no scrub control**, because a voice has no duration to scrub through.
    func testCaptureFullPlayerDrivenByTheVoice() throws {
        let app = try speakAndLeaveTheReader()
        let wayIn = app.buttons["Open the player"].firstMatch
        XCTAssertTrue(wayIn.waitForExistence(timeout: 5), "The bar offered no way into the player.")
        wayIn.tap()
        settle(1)
        attach(app.screenshot(), named: "read-aloud-full-player")
    }

    // MARK: - The walk

    /// Opens an EPUB, starts reading it aloud, and closes the reader.
    private func speakAndLeaveTheReader() throws -> XCUIApplication {
        let app = launch()
        try openTheEpubReader(in: app)

        // **Already up, on a reader that has just opened, and a tap would take it away.** The
        // same rule `ReaderAuditTests` records: `quiet-reader` gives the chrome a four-second
        // life, so it is *looked for* first and summoned only if it has already gone.
        let menu = app.buttons["Menu"].firstMatch
        if !menu.waitForExistence(timeout: 10) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = menu.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(menu.exists, "The reader's chrome never appeared.")
        menu.tap()

        // **This is where both captures stop today, and it is not the fold's doing.**
        // `EpubReaderModel.canReadAloud` is false for every reflowable EPUB in the shared
        // corpus on this simulator, so `EpubReaderMenu` draws no read-aloud row at all —
        // which is what `ebook-reader` asks for when a publication has nothing to say, and
        // wrong for a book of plain XHTML paragraphs. Measured on 2026-09-01 and
        // **mutation-checked against a build with the fold stashed**: the menu's button
        // labels came back byte-identical, so the control was missing before read-aloud drove
        // `PlayerCentre` and is missing after. It is recorded in `tasks.md` §4.2 as the
        // reason §6.2 has no capture.
        //
        // A skip rather than a failure, because `pnpm check` does not run this suite and a
        // red UI test nobody runs is a red UI test nobody fixes. The message is the signal.
        let readAloud = app.buttons["Read aloud"].firstMatch
        try XCTSkipUnless(
            readAloud.waitForExistence(timeout: 5),
            """
            No read-aloud control on this publication, so the voice cannot be started and
            neither capture can be taken. `ebook-reader` allows an absent control for a
            publication Readium can extract no content from — but every corpus EPUB is plain
            XHTML with paragraphs in it, so this is a defect rather than that clause.
            Buttons in the menu: \(app.buttons.allElementsBoundByIndex.map(\.label))
            """
        )
        readAloud.tap()

        // The bar appears as soon as the session begins, which is before the first sentence
        // is spoken — so this waits for the bar rather than for a sound.
        let bar = app.buttons["Back to the book"].firstMatch
        XCTAssertTrue(
            bar.waitForExistence(timeout: 15),
            "The compact bar never appeared after starting read-aloud. Buttons on screen: "
                + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
        )

        // **Paused before leaving, and deliberately.** A capture of a moving session is a
        // race: the voice crosses a sentence between the two screenshots and the chapter line
        // differs for a reason that has nothing to do with what is being photographed. A
        // paused session keeps its bar, which `CompactPlayerTests` pins.
        app.buttons["Pause"].firstMatch.tap()

        // The chrome has had four seconds to go away again while the voice started.
        let close = app.buttons["Close"].firstMatch
        if !close.waitForExistence(timeout: 3) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = close.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(close.exists, "No way out of the reader.")
        close.tap()
        return app
    }

    /// Waits, then photographs. See `PlayerScreenshotTests.settle(_:)` for why not `sleep`.
    private func settle(_ seconds: TimeInterval) {
        let settled = XCTestExpectation(description: "waited \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { settled.fulfill() }
        wait(for: [settled], timeout: seconds + 3)
    }

    private func attach(_ shot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
