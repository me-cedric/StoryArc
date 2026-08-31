import XCTest

// Reaching the reflowable EPUB reader — the one walk in this suite that a cover cannot
// answer, and the one that has to scroll to answer it at all.
//
// Split out of `AuditWalk.swift` because it is a different kind of thing: that file is short
// helpers over one screenful, and this is a search with a budget, a scroll depth and three
// distinct ways of coming back empty.

@MainActor
extension XCTestCase {

    /// Opens the **reflowable** EPUB reader, and says which of two things it proved.
    ///
    /// `ofFormat: "EPUB"` is as close as the shelf can get and it is not close enough. A
    /// cover's spoken label carries the format and says nothing about how the book is laid
    /// out, while a **fixed-layout** EPUB is not reflowable — `Publication.isReflowable` — and
    /// opens the comic reader, which has no typography controls, because `ebook-reader` hides
    /// them for a pre-paginated page rather than showing them disabled.
    ///
    /// `scripts/corpus.mjs` builds five EPUBs and gives two of them
    /// `<meta property="rendition:layout">pre-paginated</meta>`: `Bright Panels` and
    /// `Glasshouse`. Under the shelf's default sort — `LibraryQuery`'s `sort: .title`,
    /// ascending — those two titles sort before `Harbour Lights 01`, `Harbour Lights 02` and
    /// `The Long Field`. **That is a fact about the corpus and not about any particular
    /// device.** The sort is persisted per reader (`LibraryModel` restores
    /// `preferences.query()` on launch) and these tests reset no app state, so what order a
    /// shelf is in when a run starts is not something this file can know. Which is the reason
    /// it searches instead of assuming.
    ///
    /// **Two proofs, and only the second one is about the book.**
    ///
    /// - `app.buttons["Reading"]` is `theme.title` in `EpubReaderFeature`, drawn as a `Button`
    ///   in that reader's chrome, so it proves the *reflowable reader* is what opened.
    ///   Settings carries a row that reads *Reading* as well (`settings.reading`), but a
    ///   settings row surfaces as a cell or a static text rather than a button — which is what
    ///   `control(_:in:)` exists for — and this walk never opens Settings.
    ///   It proves nothing more than the reader: in `EpubReaderView` the chrome is a `ZStack`
    ///   sibling gated only on `isChromeVisible`, which starts `true`, so it is drawn over the
    ///   `ProgressView()` and over the failure view just as it is drawn over a page. A comment
    ///   here once claimed this wait was for the book to open. It never was.
    /// - A web view proves the book. `NavigatorHost` is what hosts it and it is built only in
    ///   `EpubReaderView`'s `else if let navigator` branch, so with no sheet up a web view
    ///   means the navigator and no web view means the spinner or a `Failure` — and a
    ///   screenshot or an audit taken then measures neither reader honestly. The one other
    ///   `WKWebView` in that module is `ThemePreview`'s, inside `ThemeSheet`, which is not
    ///   presented at the point this looks; a caller that opens the sheet first would be
    ///   asking a different question.
    ///
    /// **The scroll depth and the attempt budget are counted separately.** They used to be one
    /// number: sweep *n* swiped up *n* times and took one candidate, so an untried EPUB
    /// sitting on a screenful the walk had already looked at was scrolled past and never
    /// tried, and a sweep spent on a wrong book was a sweep of depth spent too. Now every
    /// untried candidate at a depth is taken before the walk scrolls further, and the budget
    /// is separately what stops it.
    ///
    /// Six depths rather than four because the callers do not all see the same shelf: the AX5
    /// capture in `ScreenshotTests` runs at `UICTContentSizeCategoryAccessibilityXXXL`, where
    /// a cell is taller and a screenful therefore holds fewer publications, so the same swipe
    /// passes fewer of them. Six is a budget and not a measurement — nobody has counted how
    /// many screenfuls this corpus fills at that text size — which is why running out says so
    /// in the skip rather than concluding anything.
    ///
    /// Candidates are remembered by the stable head of their label rather than by the whole of
    /// it — see ``shelfIdentity(of:endingWith:)``. Opening a publication is precisely the act
    /// that changes the tail.
    ///
    /// Relaunching between attempts rather than closing the reader: leaving is a full-screen
    /// cover's own business, the comic reader's chrome fades after four seconds, and a launch
    /// is a single call that cannot half-succeed. The cost is the scroll position, which is
    /// why each attempt swipes its way back down.
    ///
    /// **English only, deliberately unhandled.** `Reading` and the *Library* destination are
    /// hardcoded, so under `launch(language:)` this finds neither and skips. It is the same
    /// dependency `AccessibilityAuditTests` states for its Settings walk — "the groups are
    /// named by their English labels. That is a real dependency … this suite runs in the
    /// development language." A localised lookup would need the test bundle to read
    /// `EpubReaderFeature`'s own strings, which it cannot see.
    ///
    /// It skips rather than fails, and one message covers every way of coming back empty: what
    /// EPUB covers were seen at all, which were opened, which reached the reflowable reader,
    /// which reached it without a page, and what was on screen when it gave up. The terse
    /// "this device holds no EPUB" is only said when no depth showed one, because that was the
    /// message a shelf whose EPUBs merely sat low in the window used to get.
    func openTheEpubReader(in app: XCUIApplication) throws {
        let reading = app.buttons["Reading"]
        var seen: Set<String> = []
        var tried: [String] = []
        var reachedTheReader: [String] = []
        var withoutAPage: [String] = []
        var attempts = 0
        var isFirstLook = true

        depths: for depth in 0..<6 {
            while attempts < 6 {
                if !isFirstLook { app.launch() }
                isFirstLook = false
                try showTheShelf(in: app)
                for _ in 0..<depth { app.swipeUp() }

                let covers = coversOnScreen(in: app, ofFormat: "EPUB")
                seen.formUnion(covers.map { shelfIdentity(of: $0.label, endingWith: "EPUB") })
                // Nothing new here: scroll further rather than spending an attempt.
                guard let cover = covers.first(where: {
                    !tried.contains(shelfIdentity(of: $0.label, endingWith: "EPUB"))
                })
                else { continue depths }

                let candidate = shelfIdentity(of: cover.label, endingWith: "EPUB")
                tried.append(candidate)
                attempts += 1
                cover.tap()

                // A hittable action, not the first in the hierarchy: this page has duplicate
                // entries and `firstMatch` can bind to one no finger could reach.
                guard app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 5),
                      let action = app.buttons.matching(opensAPublication)
                          .allElementsBoundByIndex.first(where: \.isHittable)
                else { continue }
                action.tap()

                guard reading.waitForExistence(timeout: 15) else { continue }
                reachedTheReader.append(candidate)
                if app.webViews.firstMatch.waitForExistence(timeout: 15) { return }
                withoutAPage.append(candidate)
            }
            break
        }

        // Only once every depth has been looked at. Said before the scroll, this was the
        // message a shelf whose EPUB covers merely sat low in the window got, and it blamed
        // the device's fixtures for a walk that had not looked.
        try XCTSkipUnless(
            !seen.isEmpty,
            "This device's library showed no EPUB cover at any of the six scroll depths."
        )
        throw XCTSkip(
            """
            No EPUB on this device opened a page in the reflowable reader.
            EPUB covers seen: \(seen.sorted())
            Covers tapped: \(tried)
            Reached the reflowable reader: \(reachedTheReader)
            Reached it with no page in it: \(withoutAPage)
            Buttons on screen: \(app.buttons.allElementsBoundByIndex.map(\.label))
            """
        )
    }

    /// A cover's spoken label cut off after its format — the part of it that opening the
    /// publication cannot change.
    ///
    /// `CoverCell` builds the label with `LibraryMarks.spoken([title, subtitle, format,
    /// progress, pages], isOnDevice:isReadableNow:)`, comma-joined in that order with the
    /// `nil`s dropped, so **everything that moves is after the format**: the progress phrase
    /// appears as soon as a recorded position is above zero (`LibraryModel.readFraction`),
    /// *On this device* appears once the bytes are local — and that mark now survives a launch
    /// — and *Needs its library to be reachable* comes and goes with the source. Keying a
    /// walk's "already tried" set on the whole label meant a candidate it had just opened came
    /// back looking new and spent a second attempt on itself.
    ///
    /// Cut at the format token rather than at a part count, because the count is not fixed: a
    /// publication with no series line and no author has no subtitle, and `spoken` drops it
    /// rather than leaving a gap, so the third part of one cover's label is the format and of
    /// another's is its progress.
    ///
    /// Two publications with the same title and the same caption are one identity to this
    /// walk. That is a real limit and it is the same kind the shelf itself has.
    func shelfIdentity(of label: String, endingWith format: String) -> String {
        guard let format = label.range(of: ", \(format)") else { return label }
        return String(label[label.startIndex..<format.upperBound])
    }
}
