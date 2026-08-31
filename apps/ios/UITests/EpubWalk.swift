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
    /// - A web view proves the book. `NavigatorHost` is the only thing in that screen that
    ///   hosts one, and it is built only in the `else if let navigator` branch — so no web
    ///   view means a spinner or a `Failure`, and a screenshot or an audit taken then measures
    ///   neither reader honestly.
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
    /// it — see ``shelfIdentity(of:)``. Opening a publication is precisely the act that
    /// changes the tail.
    ///
    /// Relaunching between attempts rather than closing the reader: leaving is a full-screen
    /// cover's own business, the comic reader's chrome fades after four seconds, and a launch
    /// is a single call that cannot half-succeed. The cost is the scroll position, which is
    /// why each attempt swipes its way back down.
    ///
    /// **English only, deliberately unhandled.** `Reading` and the *Library* destination are
    /// hardcoded, so under `launch(language:)` this finds neither and skips — the same
    /// dependency `control(_:in:)` documents for itself. A localised lookup would need the
    /// test bundle to read `EpubReaderFeature`'s own strings, which it cannot see.
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
                seen.formUnion(covers.map { shelfIdentity(of: $0.label) })
                // Nothing new here: scroll further rather than spending an attempt.
                guard let cover = covers.first(where: { !tried.contains(shelfIdentity(of: $0.label)) })
                else { continue depths }

                let candidate = shelfIdentity(of: cover.label)
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

    /// The head of a cover's spoken label — the part that does not move when the publication
    /// is read or downloaded.
    ///
    /// `CoverCell` builds the label as `LibraryMarks.spoken([title, subtitle, format,
    /// progress, pages], isOnDevice:isReadableNow:)`, comma-joined in that order, so
    /// everything mutable is in the tail: the progress phrase appears once a publication has
    /// been opened past the first page, and the *Downloaded* mark appears once its bytes are
    /// on the device — and it now survives a launch. Keying a walk's "already tried" set on
    /// the whole label meant a candidate came back looking new and spent a second attempt.
    ///
    /// The first three parts are the title, the caption under it and the format. Two
    /// publications agreeing on all three would be one identity to this walk; nothing in
    /// `scripts/corpus.mjs` does.
    func shelfIdentity(of label: String) -> String {
        label.components(separatedBy: ", ").prefix(3).joined(separator: ", ")
    }
}
