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
/// library holds no EPUB at all. Each walk opens `Harbour Lights 01` or another book by name.
@MainActor
final class ReadAloudPlayerTests: XCTestCase {

    /// What held the UI focus just before the voice started and just after its bar appeared.
    /// Set by ``speakAndLeaveTheReader(opening:)``, read by the focus test.
    private var focusAroundStart: (before: String?, after: String?)?

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

    /// The reader that stopped the voice, saying so over its page.
    ///
    /// `ebook-reader`, *Opening a different publication*: "the listener is told once that the
    /// voice stopped, rather than discovering it by silence". The voice is started on whichever
    /// reflowable EPUB the shared walk finds, the reader is closed with the voice carrying on,
    /// and a **different** reflowable EPUB is opened by name — so what this photographs is the
    /// new book's page with `VoiceStoppedBanner` over it, naming the old one.
    ///
    /// It waits for the banner itself rather than for the web view: the word is armed as the
    /// book opens and leaves six seconds later, and a walk that first waited twenty seconds for
    /// a page could photograph a page the word had already left.
    ///
    /// **Both books are opened by name**, for the reason `SweepEpubReader.openReader` gives:
    /// the shared search tries the two fixed-layout EPUBs first and spends most of a minute
    /// learning that neither opens a page. `Harbour Lights 01` and `The Long Field` are the
    /// corpus's reflowable books, and which one speaks is then known rather than read back.
    func testCaptureVoiceStoppedByAnotherBook() throws {
        let app = try speakAndLeaveTheReader(opening: "Harbour Lights 01")
        try openReadAloudBook(named: "The Long Field", in: app, expectingAPage: false)

        let banner = app.descendants(matching: .any).matching(identifier: "voice-stopped").firstMatch
        XCTAssertTrue(
            banner.waitForExistence(timeout: 30),
            "Opening The Long Field over the voice showed no word that the voice stopped. "
                + "Static texts: \(app.staticTexts.allElementsBoundByIndex.map(\.label))"
        )
        settle(0.5)
        attach(app.screenshot(), named: "voice-stopped-in-reader")
    }

    /// The shelf, saying so when an audiobook started from it stopped the voice.
    ///
    /// `listen(to:at:)` presents no screen — the compact bar is the surface a listener gets — so
    /// the word lands on the shell, over whatever the listener was looking at, as
    /// `VoiceStoppedCapsule`. The bar below it has already started saying the *new* book's
    /// name, which is why the word is at the top and not beside the bar.
    func testCaptureVoiceStoppedByAnAudiobook() throws {
        let app = try speakAndLeaveTheReader(opening: "Harbour Lights 01")
        // *Sea Room* is the corpus's single-file audiobook, and the name `AudiobookWalk`
        // already depends on. **This line named *The Peregrine* and no generator writes one:**
        // it is a failed *download* record, injected by `SweepDownloads` as JSON and never a
        // file, so no shelf on any device holds a cover for it and this walk always failed on
        // "No cover called The Peregrine on this device's shelf". `scripts/corpus.mjs` writes
        // two audiobooks — `Sea Room.m4b` and the `Tidal Voices` folder — and this capture
        // needs one, so it names one that exists rather than growing the corpus.
        try openReadAloudBook(named: "Sea Room", in: app, expectingAPage: false)

        let capsule = app.descendants(matching: .any).matching(identifier: "voice-stopped").firstMatch
        XCTAssertTrue(
            capsule.waitForExistence(timeout: 30),
            "Starting an audiobook over the voice showed no word that the voice stopped. "
                + "Static texts: \(app.staticTexts.allElementsBoundByIndex.map(\.label))"
        )
        settle(0.5)
        attach(app.screenshot(), named: "voice-stopped-on-shelf")
    }

    /// The bar over a running voice: its elements in reading order, each named, and nothing
    /// taken from the listener when it appeared.
    ///
    /// Task 2.4, `ebook-reader`'s *Reaching the transport without touch*. `PlayerDockFocusTests`
    /// reads the source and `PlayerLabelsTests` reads the decisions; neither says what a screen
    /// reader is handed. This asks the running app: the accessibility tree lists the way back,
    /// the way into the player, play or pause, and stop, in that order, and the way back carries
    /// the publication's whole name and the chapter as its value, because the row cuts them.
    ///
    /// **What XCUITest cannot see, and this does not claim.** The VoiceOver cursor is not
    /// readable from a test, and a simulator cannot run VoiceOver. The focus clause is asserted
    /// as far as a test can reach: the element the focus system holds is the same before the
    /// session starts and after its bar is up. A bar that moved the cursor with
    /// `accessibilityFocused` is still caught by `PlayerDockFocusTests`. The spoken walk and
    /// Full Keyboard Access are on the device checklist.
    func testTheVoiceBarIsReadInOrderAndTakesNoFocus() throws {
        let app = try speakAndLeaveTheReader()

        let wayBack = app.buttons["Back to the book"].firstMatch
        // A minimised tab bar holds the bar inline, without the way back. A swipe down on the
        // shelf brings the full bar back.
        if !wayBack.waitForExistence(timeout: 3) { app.swipeDown() }
        XCTAssertTrue(wayBack.waitForExistence(timeout: 5), "The bar offered no way back to the book.")
        // Play or pause, whichever the session is in when the bar is read.
        let labels = app.buttons.allElementsBoundByIndex.map(\.label)
        let transport = labels.contains("Pause") ? "Pause" : "Play"
        let order = ["Back to the book", "Open the player", transport, "Stop"]
        let places = order.map { labels.firstIndex(of: $0) }
        XCTAssertFalse(places.contains(nil), "The bar is missing an element of \(order). Buttons: \(labels)")
        XCTAssertEqual(
            places.compactMap { $0 }.sorted(),
            places.compactMap { $0 },
            "A screen reader meets the bar's elements out of order: \(order) sit at \(places) in \(labels)"
        )

        // The title is the row's first text, and its label is whole however the row cuts it.
        let title = wayBack.staticTexts.firstMatch.label
        let value = wayBack.value as? String ?? ""
        XCTAssertFalse(title.isEmpty, "The way back draws no title.")
        XCTAssertTrue(
            value.contains(title),
            "The way back announces \"\(value)\", which leaves out the title \"\(title)\" the row may cut."
        )

        let around = try XCTUnwrap(focusAroundStart, "The walk recorded no focus.")
        XCTAssertEqual(around.before, around.after, "Starting the voice moved the focus.")

        try reportOnly(app, named: "Library with the read-aloud bar")
    }

    /// The walk of ``speakAloud(opening:pausing:)``, paused, with the focus kept for the focus test.
    ///
    /// A book named, not the first EPUB cover a search meets (task 25.5): a shelf grouped by
    /// series, or one with server titles beside the corpus, showed the search no EPUB cover,
    /// and the walk skipped or opened a book that does not read aloud.
    private func speakAndLeaveTheReader(opening title: String = "Harbour Lights 01") throws -> XCUIApplication {
        let walk = try speakAloud(opening: title)
        focusAroundStart = walk.focus
        return walk.app
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
