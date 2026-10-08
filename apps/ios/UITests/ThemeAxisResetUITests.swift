import XCTest

/// `reader-theming-and-page-transitions` 3.5: a reader who changes an axis and then resets it
/// is on the same paragraph afterwards.
///
/// `ThemeAxisResetTests` can only pin the source order of the reset, because no unit host lays
/// out a navigator. This is the behaviour: a real reflowable book on a simulator, turned to a
/// page in the middle of a chapter, an axis moved and then reset through the slider's long
/// press, and the paragraph on the page read before, after the move and after the reset.
///
/// `ebook-reader`: "the reading position is preserved to the paragraph, not the page number".
/// A reflow re-paginates the chapter, and `EpubReaderModel.applyTheme` returns to the stored
/// locator once it has settled.
///
/// **The book is `Fixture Publication`** (`packages/test-fixtures/ebooks/fixture.epub`, forty
/// paragraphs a chapter, each reading "Chapter 1, paragraph 31."), because a chapter long
/// enough to span many pages is what lets a landing by progression alone drift by more than a
/// paragraph. `The Long Field` has fourteen paragraphs a chapter and cannot show it.
/// `node scripts/corpus.mjs` does not write the fixture; copy it into the app's
/// `Documents/Corpus` beside the corpus, or the test falls back to `The Long Field`.
///
/// **A limit, measured on 2026-10-08.** With the `go(to:)` call in `applyTheme` removed this test
/// still passes, on both books: Readium's iOS navigator keeps the reader on the same paragraph
/// across a preferences change by itself (paragraph 13, 13 and 13 on the fixture). So on iOS
/// this proves the position survives the reset, not that the call is what carries it.
@MainActor
final class ThemeAxisResetUITests: XCTestCase {

    /// Paragraphs of drift the test tolerates. The first paragraph on a page can be the tail of
    /// the one before it, depending on where the column falls, so one is not drift.
    private static let tolerance = 1

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTheReadingPositionSurvivesAnAxisChangeAndItsReset() throws {
        let app = sweepLaunch()
        try openTheReflowableBook(in: app)

        // A page in the middle of a chapter, so there is somewhere to drift from. A chapter's
        // first page begins at its first paragraph whatever the layout, so it proves nothing.
        var turns = 0
        while turns < 12, (firstParagraph(in: app) ?? 0) < 10 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            hold(1.2)
            turns += 1
        }
        let before = try XCTUnwrap(firstParagraph(in: app), "No paragraph is readable. \(visibleText(in: app))")
        try XCTSkipIf(before < 10, "No mid-chapter page in \(turns) turns; the page begins at \(before).")

        // Margins, the axis that reflows the most: a narrower column puts far fewer words on a
        // page, so a reader landing by progression alone is many paragraphs away.
        try openTheAxes(in: app)
        var slider = try axisSlider("Margins", in: app)
        // Through the middle to the far right, whatever the slider started at.
        slider.adjust(toNormalizedSliderPosition: 0.3)
        hold(1)
        let start = slider.value as? String
        slider.adjust(toNormalizedSliderPosition: 0.95)
        hold(1.5)
        XCTAssertNotEqual(slider.value as? String, start, "The slider did not move, so there is nothing to reset.")
        let moved = slider.value as? String

        try closeTheSheets(in: app)
        let afterChange = try XCTUnwrap(
            firstParagraph(in: app), "No paragraph after the change. \(visibleText(in: app))"
        )
        XCTAssertLessThanOrEqual(
            abs(afterChange - before), Self.tolerance,
            "Changing an axis moved the reader from paragraph \(before) to \(afterChange)."
        )

        try openTheAxes(in: app)
        slider = try axisSlider("Margins", in: app)
        resetThroughLongPress(slider)
        XCTAssertNotEqual(slider.value as? String, moved, "The long press did not reset the axis.")

        try closeTheSheets(in: app)
        let afterReset = try XCTUnwrap(firstParagraph(in: app), "No paragraph after the reset. \(visibleText(in: app))")
        XCTAssertLessThanOrEqual(
            abs(afterReset - before), Self.tolerance,
            "Resetting an axis moved the reader from paragraph \(before) to \(afterReset)."
        )
    }

    private func axisSlider(_ name: String, in app: XCUIApplication) throws -> XCUIElement {
        let slider = app.sliders[name]
        XCTAssertTrue(scrollTo(slider, in: app, swipes: 8), "The axes screen offers no \(name) slider.")
        return slider
    }

    /// The fixture by name, then *The Long Field*, then the shared search.
    ///
    /// By name first because the search tries the two fixed-layout books before it reaches a
    /// reflowable one and waits fifteen seconds on each.
    private func openTheReflowableBook(in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        for title in ["Fixture Publication", "The Long Field"] {
            let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
            var cover: XCUIElement?
            for _ in 0..<8 where cover == nil {
                cover = wanted.allElementsBoundByIndex.first(where: \.isHittable)
                if cover == nil { app.swipeUp() }
            }
            guard let cover else { continue }
            cover.tap()
            if app.buttons.matching(opensAPublication).firstMatch.waitForExistence(timeout: 8),
               let action = app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable) {
                action.tap()
                if app.webViews.firstMatch.waitForExistence(timeout: 20) {
                    hold(3)
                    return
                }
            }
            app.launch()
            try showTheShelf(in: app)
        }
        app.launch()
        try openTheEpubReader(in: app)
        hold(3)
    }

    // MARK: - Reading the page

    /// The text the web view puts on screen, in the order it lists it.
    ///
    /// By where the column starts, because neither `frame` nor `isHittable` can be trusted
    /// whole. The page is a set of columns: the one showing starts at the margin, the ones to
    /// come start a page width further right, and the ones already read report an x of 0.
    /// `isHittable` answers correctly for most elements and reports an invalid activation point
    /// for a paragraph split across two columns, which XCTest records as a failure.
    private func visibleText(in app: XCUIApplication) -> [String] {
        let width = app.frame.width
        return app.webViews.firstMatch.staticTexts.allElementsBoundByIndex
            .filter { $0.frame.minX >= 10 && $0.frame.minX < width && $0.frame.width > 0 }
            .map(\.label)
    }

    /// The number of the first paragraph on the page. The fixture says it in words, "Chapter 1,
    /// paragraph 31."; the corpus books end each paragraph with `<chapter>.<paragraph>`.
    private func firstParagraph(in app: XCUIApplication) -> Int? {
        for text in visibleText(in: app) {
            if let words = text.range(of: #"paragraph (\d+)"#, options: .regularExpression) {
                return Int(text[words].dropFirst("paragraph ".count))
            }
            if let dotted = text.range(of: #"\d+\.(\d+)\.?\s*$"#, options: .regularExpression) {
                let number = text[dotted].trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                return number.split(separator: ".").last.flatMap { Int($0) }
            }
        }
        return nil
    }

    // MARK: - The sheets

    /// A long press on the track, a third of its length from the thumb.
    ///
    /// **Not on the thumb, and that is a finding.** Measured on 2026-10-08 at six points along
    /// a slider held at its far end: a press within about thirty points of the thumb did nothing
    /// and a press at 0.8 or 0.7 of the track reset the axis every time. The slider takes a
    /// touch near its thumb for its own drag, and the `simultaneousGesture` reset never fires
    /// there. `reading-themes` asks for "a long press on a slider"; a reader who presses the
    /// thumb itself gets nothing. The test presses where the reset does take, and the report
    /// names the gap.
    ///
    /// **Up to two presses, stopping once the value moves.** A first press was ignored now and
    /// then. A reset that never takes still fails: the caller compares the value afterwards.
    private func resetThroughLongPress(_ slider: XCUIElement) {
        for _ in 0..<2 {
            let before = slider.value as? String
            hold(0.5)
            let thumb = slider.normalizedSliderPosition
            let away = thumb > 0.5 ? thumb - 0.3 : thumb + 0.3
            slider.coordinate(withNormalizedOffset: CGVector(dx: away, dy: 0.5)).press(forDuration: 1.2)
            hold(1.5)
            if (slider.value as? String) != before { return }
        }
    }

    private func openTheAxes(in app: XCUIApplication) throws {
        try XCTUnwrap(revealed("Menu", in: app), "The reader revealed no menu to open.").tap()
        for _ in 0..<5 where hittableRow("Reading themes", in: app, timeout: 1) == nil {
            app.swipeUp()
            hold(0.7)
        }
        try XCTUnwrap(hittableRow("Reading themes", in: app), "The menu offers no reading-themes row.").tap()
        for _ in 0..<6 where hittableRow("Customise", in: app, timeout: 1) == nil {
            app.swipeUp()
            hold(0.5)
        }
        try XCTUnwrap(hittableRow("Customise", in: app), "The theme sheet offers no Customise.").tap()
    }

    /// Backs out of every sheet, each by its own control, and lets the chrome fade.
    private func closeTheSheets(in app: XCUIApplication) throws {
        for _ in 0..<3 {
            guard let done = hittableRow("Done", in: app, timeout: 3) else { break }
            done.tap()
            hold(1)
        }
        XCTAssertTrue(app.buttons["Done"].waitForNonExistence(timeout: 8), "A sheet is still up over the page.")
        hold(2)
    }
}
