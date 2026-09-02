import Foundation
import Testing

@testable import LibraryFeature

/// What the library's toolbar puts in front of a reader, counted rather than described.
///
/// A design review on 2026-09-01 called this "five unlabelled icons in a row". It was
/// **six** — the review undercounted — and the first thing this file did was prove that,
/// with the assertion below set to `6` against the unchanged sources. That run is the only
/// reason the number in `design.md` is a measurement rather than a second opinion.
///
/// `library-browsing`, *The controls that change the view are grouped*: "the choices — what
/// is shown, how it is grouped, how it is sorted, what is filtered out — are reached through
/// named menus rather than as separate unlabelled buttons", and "a control that changes
/// *mode* rather than presenting a choice may stand on its own".
///
/// **This reads source text**, which is the same trade `GlassIsUntintedTests` and
/// `SkippedNoticeTimerTests` make and explain: composing a `ToolbarContent` needs a window,
/// `swift test` runs on the host, and what regressed here is not a rendered pixel but the
/// number of items declared in one placement. That is a thing text can count exactly.
///
/// The picture is the other half and is not optional — `docs/designs/screenshots/`
/// `quieter-toolbar-2026-09-02/` holds the before and after at two text sizes and two
/// appearances.
@Suite("The library toolbar keeps two controls and two menus")
struct LibraryToolbarTests {

    /// A source file in the package under test, reached from this file rather than discovered.
    ///
    /// Built from `#filePath`, so it is inside the checkout being compiled by construction.
    /// Walking up looking for a marker leaves it: this repository nests agent worktrees at
    /// `.claude/worktrees/<name>/`, and a walk climbs out of the one under test.
    private static func source(_ relativePath: String) -> String {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = package.appending(path: relativePath)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fatalError("\(relativePath) is not at \(file.path) — has it moved?")
        }
        return text
    }

    /// A file's code, with `//` prose removed.
    ///
    /// The comment above the toolbar names every control it used to hold and says what
    /// happened to each. A guard that counted those words would be measuring the
    /// documentation of the change rather than the change.
    private static func code(of relativePath: String) -> String {
        source(relativePath)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    private static let toolbar = code(of: "Sources/LibraryFeature/LibraryToolbar.swift")
    private static let controls = code(of: "Sources/LibraryFeature/LibraryBrowsingControls.swift")

    /// One toolbar item: what it is, the key it is named by, and where it is declared.
    ///
    /// The *path* rather than the source text. A tuple carrying the whole file put four
    /// hundred lines of Swift into the name of every failing case, which buries the sentence
    /// that says what went wrong.
    struct Item: Sendable, CustomTestStringConvertible {
        let what: String
        let key: String
        let file: String

        var testDescription: String { "\(what) — \(key)" }
    }

    /// The four items the toolbar is allowed to put in `.primaryAction`, and the key each
    /// one is named by.
    ///
    /// Held as a table rather than as four assertions so that adding a fifth control cannot
    /// be done without editing this list — which is the point of counting at all.
    private static let items: [Item] = [
        Item(what: "select", key: "library.select", file: "LibraryToolbar.swift"),
        Item(what: "the view menu", key: "library.view", file: "LibraryBrowsingControls.swift"),
        Item(what: "the filter menu", key: "library.filter", file: "LibraryFilterMenu.swift"),
        Item(what: "add books", key: "library.addSource", file: "AddSourceMenu.swift"),
    ]

    @Test("There are four items in the primary action, not six")
    func fourItems() {
        let found = Self.toolbar.ranges(of: "ToolbarItem(placement: .primaryAction)").count
        #expect(
            found == 4,
            """
            The library toolbar declares \(found) items in `.primaryAction`, and the shape \
            `library-browsing` asks for is four: select, the view menu, the filter menu and \
            add books. There were six before this change — the review that reported the \
            defect counted five and undercounted — and every one added back is another \
            unlabelled glyph in a row of them.
            """
        )
    }

    /// The two that folded in are gone from the toolbar, and are not merely renamed.
    ///
    /// A count of four is satisfiable by deleting a control instead of folding it, which
    /// would lose a choice rather than group it. The choices themselves are asserted present
    /// in ``theFoldedChoicesSurvive``.
    @Test("Neither the availability control nor the layout toggle is a toolbar item")
    func theTwoFoldedControlsAreGone() {
        #expect(
            !Self.toolbar.contains("ScopeMenu("),
            "the availability control is still mounted in the toolbar rather than folded in"
        )
        #expect(
            !Self.toolbar.contains("LayoutToggle("),
            "the layout toggle is still mounted in the toolbar rather than folded in"
        )
    }

    /// Folding is not deleting: both choices are still reachable, inside the view menu.
    @Test("The folded choices are still offered, inside the view menu")
    func theFoldedChoicesSurvive() {
        #expect(
            Self.controls.contains("$availability"),
            "the view menu decides no availability — narrowing to what is on this device was lost"
        )
        #expect(
            Self.controls.contains("model.layout"),
            "the view menu decides no layout — the grid and list choice was lost"
        )
        #expect(
            Self.controls.contains("model.query.sort"),
            "the view menu decides no ordering — the sort choice was lost"
        )
    }

    /// Select stays on its own, and this is the assertion that says **why**.
    ///
    /// It changes the surface's *mode*: every cover becomes a checkbox and the shelf stops
    /// being a shelf until the reader leaves again. The other three present a choice and
    /// leave the surface as it was. A mode switch sitting inside a menu of choices is how a
    /// reader lands in selection without having asked for it — they went looking for a sort
    /// and came back holding a checklist — which is why `library-browsing` allows exactly
    /// this one control to stand alone and why the allowance is worded as *changes mode*
    /// rather than *is important*.
    @Test("Select is a control of its own, because it changes mode rather than offering a choice")
    func selectStandsAlone() {
        // The toolbar builds no menu of its own: the two it mounts are types of their own,
        // and the add menu is a third. So no `Menu {` here at all is the honest way to say
        // that nothing in this file wraps `selection.begin()` in one.
        #expect(
            !Self.toolbar.contains("Menu {"),
            """
            The toolbar has grown a menu of its own. If select has been folded into it, a \
            reader choosing a sort can now enter selection by accident; if something else \
            has, it belongs in one of the two menus that already exist.
            """
        )
        #expect(
            Self.toolbar.contains("selection.begin()"),
            "the way into selection has left the toolbar"
        )
        // **This assertion used to read `.disabled(selection.isActive)`** — select stayed
        // mounted and dead through the mode, on the argument that a control should not move
        // while a reader is using it. The argument was sound and the premise was not: the
        // way *out* was an item inside the selection's own bottom bar, so a reader who had
        // entered the mode had a dead *Select* in the navigation bar and a live *Done* at
        // the foot of the screen, which is not where any Apple app puts an exit. Select and
        // Done are one switch in one slot now — Photos, Files and Mail all do exactly this
        // — and the control still does not move, because the slot does not.
        //
        // `BulkSelectionChromeTests` owns the other half: that *Done* is in the toolbar and
        // no longer in the bar, and that the toolbar's exit is not gated on what is picked.
        #expect(
            !Self.toolbar.contains(".disabled(selection.isActive)"),
            """
            *Select* is mounted-but-disabled during a selection again. The trailing slot is \
            the mode's one switch: it says *Select* on the way in and *Done* on the way \
            out, and a dead *Select* beside a live *Done* is two controls arguing.
            """
        )
        #expect(
            Self.toolbar.contains("if selection.isActive {"),
            """
            The toolbar does not change while a selection is running, so either the way out \
            is somewhere else — the bottom bar, which is the shape being replaced — or the \
            three view choices are still offered mid-pick and can carry picks off screen.
            """
        )
    }

    /// Every standalone control names itself, whatever it draws.
    ///
    /// `library-browsing`: "every one of them names itself to assistive technology whatever
    /// it draws". A toolbar item is drawn as a glyph, and a `Label { Text } icon: { Image }`
    /// is what gives it a name anyway — a bare `Image` in the label position is a control
    /// VoiceOver can only call "button".
    @Test("Each of the four names itself in words", arguments: Self.items)
    func eachItemIsNamed(_ item: Item) {
        let declaration = Self.code(of: "Sources/LibraryFeature/\(item.file)")
        #expect(
            declaration.contains("Text(\"\(item.key)\", bundle: .module)"),
            """
            \(item.what) does not look up `\(item.key)`, so it has no name for assistive \
            technology beyond the word "button".
            """
        )
    }

    /// And the name exists in all four languages.
    ///
    /// `localization`: the build "fails if any supported language is missing a key that
    /// English defines". `pnpm strings:ios` is that gate for the whole app; this is the same
    /// question asked of the four keys this toolbar depends on, inside the suite that owns
    /// them — the shape `ReaderMenuTests` uses for the reader's menu rows.
    @Test("Each name is translated into all four languages", arguments: Self.items)
    func eachNameIsTranslated(_ item: Item) throws {
        let catalogue = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/LibraryFeature/Resources/Localizable.xcstrings")
        let data = try #require(
            try? Data(contentsOf: catalogue),
            "the library's string catalogue is not at \(catalogue.path)"
        )
        let parsed = try #require(
            try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            "the library's string catalogue is not a catalogue this test can read"
        )
        let strings = try #require(parsed["strings"] as? [String: Any])
        let record = try #require(
            strings[item.key] as? [String: Any],
            "the catalogue has no `\(item.key)`, so \(item.what) renders its own key"
        )
        let localizations = record["localizations"] as? [String: Any] ?? [:]
        for language in ["en", "fr", "de", "es"] {
            #expect(
                localizations[language] != nil,
                "`\(item.key)` — \(item.what) — has no \(language) translation"
            )
        }
    }
}
