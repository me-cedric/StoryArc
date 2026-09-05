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
        try openPublication(named: "The Long Field", in: app, expectingAPage: false)

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
        try openPublication(named: "Sea Room", in: app, expectingAPage: false)

        let capsule = app.descendants(matching: .any).matching(identifier: "voice-stopped").firstMatch
        XCTAssertTrue(
            capsule.waitForExistence(timeout: 30),
            "Starting an audiobook over the voice showed no word that the voice stopped. "
                + "Static texts: \(app.staticTexts.allElementsBoundByIndex.map(\.label))"
        )
        settle(0.5)
        attach(app.screenshot(), named: "voice-stopped-on-shelf")
    }

    // MARK: - The walk

    /// Opens one publication by name from the shelf, scrolling to find it.
    ///
    /// The same walk `SweepEpubReader.openReflowable` makes, with the proof made optional: an
    /// audiobook opens no page, and `AudiobookWalk` waits for the bar instead — which here is
    /// already up for the voice, so it proves nothing. The word itself is the proof the two
    /// captures above wait for.
    private func openPublication(named title: String, in app: XCUIApplication, expectingAPage: Bool = true) throws {
        try showTheShelf(in: app)
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        var cover: XCUIElement?
        for _ in 0..<8 where cover == nil {
            cover = wanted.allElementsBoundByIndex.first(where: \.isHittable)
            if cover == nil { app.swipeUp() }
        }
        try XCTUnwrap(cover, "No cover called \(title) on this device's shelf.").tap()
        XCTAssertTrue(
            app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 8),
            "The page for \(title) offered no way to open it."
        )
        try XCTUnwrap(
            app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable)
        ).tap()
        if expectingAPage {
            XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20), "\(title) opened no page.")
        }
    }

    /// Opens an EPUB, starts reading it aloud, and closes the reader.
    ///
    /// - Parameter title: a reflowable EPUB to open by name, or `nil` to let the shared search
    ///   in `EpubWalk` find one — which skips, rather than fails, on a device without any.
    private func speakAndLeaveTheReader(opening title: String? = nil) throws -> XCUIApplication {
        let app = launch()
        if let title {
            try openPublication(named: title, in: app)
        } else {
            try openTheEpubReader(in: app)
        }

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

        // **The menu is scrolled first, and an hour went into learning why.** Read-aloud is
        // the last row of the second section and sits below the fold on an iPhone. A SwiftUI
        // `List` is lazy, so a row that has never been on screen is in no accessibility tree
        // — the query came back empty and the walk read that as "this publication cannot be
        // spoken", which is a real state `ebook-reader` allows and was the wrong answer here.
        // Proven by forcing the row to render unconditionally: the query still found nothing,
        // which ruled the app out and left the query. Scrolling is the fix.
        let readAloud = app.buttons["Read aloud"].firstMatch
        var swipes = 0
        while !readAloud.exists, swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        try XCTSkipUnless(
            readAloud.waitForExistence(timeout: 3),
            """
            No read-aloud control on this publication after \(swipes) swipe(s), so the voice
            cannot be started and neither capture can be taken. `ebook-reader` allows an absent
            control for a publication Readium can extract no content from, which is what this
            would mean if the row really is not there.
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
