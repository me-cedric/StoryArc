import XCTest

/// The walk every read-aloud capture shares: open a reflowable EPUB, start the voice, leave the reader.
///
/// Split out of `ReadAloudPlayerTests` when `ReadAloudShellTests` wanted it too, for the reason
/// `AudiobookWalk` is one copy: two copies of a walk drift.
@MainActor
extension XCTestCase {

    /// The formats these walks open, which is what the shelf is filtered to.
    var readAloudFormats: [String] { ["epub", "m4b", "mp3", "flac", "ogg", "audioFolder"] }

    /// Opens one publication by name from the shelf, scrolling to find it.
    ///
    /// The same walk `SweepEpubReader.openReflowable` makes, with the proof made optional: an
    /// audiobook opens no page, and `AudiobookWalk` waits for the bar instead — which here is
    /// already up for the voice, so it proves nothing. The word itself is the proof the two
    /// captures above wait for.
    func openReadAloudBook(named title: String, in app: XCUIApplication, expectingAPage: Bool = true) throws {
        try showTheShelf(in: app)
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        var cover: XCUIElement?
        for _ in 0..<8 where cover == nil {
            // **Hittable is not enough, and a swipe is too much.** The reflowable books sit in
            // the shelf's last visible row with their centres under the floating tab bar, so a
            // hittable cover tapped there taps the bar; a `swipeUp()` then flung the row a whole
            // screen to the top, under the header and the failure notice, and the tap landed on
            // those instead. Both photographed the shelf and called it a page that offered no
            // way to open it. So the cover is taken only with its centre clear of both, and the
            // shelf is moved a third of a screen at a time by a drag, which does not fling.
            let clearOfTheHeader: CGFloat = 200
            let clearOfTheBar = app.frame.maxY - 160
            let onScreen = wanted.allElementsBoundByIndex.filter(\.exists)
            cover = onScreen.first {
                $0.isHittable && $0.frame.midY > clearOfTheHeader && $0.frame.midY < clearOfTheBar
            }
            if cover == nil {
                let tooHigh = onScreen.contains { $0.frame.midY <= clearOfTheHeader && $0.frame.maxY > 0 }
                let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: tooHigh ? 0.4 : 0.7))
                let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: tooHigh ? 0.7 : 0.4))
                from.press(forDuration: 0.1, thenDragTo: to)
                hold(1)
            }
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
    /// - Parameter leavingTheReader: `false` returns with the reader open and the voice running.
    func speakAloud(
        opening title: String? = nil,
        pausing: Bool = true,
        leavingTheReader: Bool = true
    ) throws -> (app: XCUIApplication, focus: (before: String?, after: String?)) {
        // **Filtered to the two formats these walks open, so nothing scrolls.** With the shelf
        // reduced to EPUBs and audiobooks every book these walks name is in the first two rows.
        // The filter was added while chasing a cover that opened nothing at any position; that
        // turned out to be the Library split's dead value link (see `OpenPublicationRoute`),
        // not the scroll — and the filter is kept because a walk that scrolls a lazy grid to a
        // named cell is a walk that flakes.
        let app: XCUIApplication
        if let title {
            // **Issues, not series.** The shelf's default collapses a run into one cell
            // labelled with the series name, so `Harbour Lights 01` is not on it — the cover
            // there says `Harbour Lights`. Both books this walk opens by name are issues of a
            // run, so the walk states the grouping it needs. See `LibraryGrouping`.
            app = sweepLaunch(formats: readAloudFormats, grouping: "issues")
            try openReadAloudBook(named: title, in: app)
        } else {
            app = launch()
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
        let focusBefore = uiFocus(in: app)
        readAloud.tap()

        // The bar appears as soon as the session begins, which is before the first sentence
        // is spoken — so this waits for the bar rather than for a sound. Its stop control,
        // because the row's own name depends on the tab bar: a walk that scrolled the shelf
        // minimised it, and an inline bar's row opens the player instead of the book.
        let bar = app.buttons["Stop"].firstMatch
        XCTAssertTrue(
            bar.waitForExistence(timeout: 15),
            "The compact bar never appeared after starting read-aloud. Buttons on screen: "
                + "\(app.buttons.allElementsBoundByIndex.map(\.label))"
        )

        let focus = (before: focusBefore, after: uiFocus(in: app))
        if !leavingTheReader { return (app, focus) }

        // **Paused before leaving, and deliberately.** A capture of a moving session is a
        // race: the voice crosses a sentence between the two screenshots and the chapter line
        // differs for a reason that has nothing to do with what is being photographed. A
        // paused session keeps its bar, which `CompactPlayerTests` pins.
        if pausing { app.buttons["Pause"].firstMatch.tap() }

        // The chrome has had four seconds to go away again while the voice started.
        let close = app.buttons["Close"].firstMatch
        if !close.waitForExistence(timeout: 3) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = close.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(close.exists, "No way out of the reader.")
        close.tap()
        backToTheShelf(in: app)
        return (app, focus)
    }

    /// What the focus system holds, as a label, or nil when it holds nothing.
    ///
    /// The UI focus, not the screen reader's cursor, which a test cannot read.
    func uiFocus(in app: XCUIApplication) -> String? {
        let held = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return held.exists ? "\(held.elementType.rawValue):\(held.label)" : nil
    }

    /// Closing the reader lands on the publication's page — the Library split's detail column,
    /// collapsed to one — and tapping the Library tab does not pop it. Back until the shelf's
    /// own bar is there, so the next book can be chosen from it.
    func backToTheShelf(in app: XCUIApplication) {
        for _ in 0..<3 where !app.navigationBars["Library"].exists {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.waitForExistence(timeout: 3) else { break }
            back.tap()
            hold(1)
        }
    }
}
