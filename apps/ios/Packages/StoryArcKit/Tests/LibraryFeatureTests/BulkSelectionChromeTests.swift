import Foundation
import Testing

@testable import LibraryFeature

/// The shape of the chrome a selection puts up, and the one thing it must not do.
///
/// **The defect was a shape, not a missing inset.** Measured on a booted iPhone 17 Pro on
/// 2026-09-02 with the shelf scrolled to its end: the last row of covers *did* clear the
/// bar, so the safe-area inset worked. Everything else about it was wrong. It drew
/// `storyArcGlass(in: Rectangle())` — full bleed, with a hard top edge that sliced cover
/// captions in half as they scrolled under it — it carried its own count and its own
/// *Done*, its three actions were `.labelStyle(.iconOnly)`, and it was **stacked above the
/// rounded glass tab bar**: two bottom bars, of two shapes, at once. See
/// `docs/designs/screenshots/cover-grid-2026-09-02/ios-library-end.png`.
///
/// Photos, Files and Mail on iOS 26 all answer a selection the same way, and the three
/// halves of that answer are what this file pins: **the count is the navigation title**, so
/// no bottom bar has to carry a label; **the way out is the toolbar's trailing item**, where
/// a reader's eye already goes; and **the actions are a floating glass capsule that
/// *replaces* the tab bar** rather than stacking above it — which is the part that fixes the
/// "two bars" look, and the reason ``theTabBarIsNotUpWhileTheActionsAre`` exists.
///
/// **This reads source text**, and the count and the way out are asserted as values next
/// door in ``LibrarySelectionTests``. Where a modifier is mounted and what shape a glass
/// container is given cannot be composed without a window — `swift test` runs on the host —
/// which is the trade `GlassIsUntintedTests` and `LibraryToolbarTests` make and explain. It
/// cannot see a rendered pixel; it can see the modifier that made the pixel wrong.
///
/// The picture is the other half and is owed: `testCaptureLibrarySelectingAtTheEnd` for the
/// end of the scroll, and `LibrarySelectionCapture`'s two walks for the capsule live and at
/// the text size where the action names give way to their glyphs.
@Suite("A selection replaces the tab bar rather than stacking on it")
struct BulkSelectionChromeTests {

    // MARK: - Where the chrome is mounted

    /// A source file in the package under test, reached from `#filePath` rather than found.
    ///
    /// So it is inside the checkout being compiled, by construction. Walking up looking for
    /// a marker leaves it: this repository nests agent worktrees at `.claude/worktrees/`,
    /// and a walk climbs out of the one under test.
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
    /// Every one of these files explains the defect it fixes, and those comments name the
    /// tab bar, the rectangle and the icon-only labels in order to say they are gone. A
    /// guard that searched the prose would pass on the documentation of the change.
    private static func code(of relativePath: String) -> String {
        source(relativePath)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    private static let view = code(of: "Sources/LibraryFeature/LibraryView.swift")
    private static let toolbar = code(of: "Sources/LibraryFeature/LibraryToolbar.swift")
    private static let bar = code(of: "Sources/LibraryFeature/BulkActionBar.swift")
    private static let shelfActions = code(of: "Sources/LibraryFeature/ShelfBulkActions.swift")

    /// **The assertion that pins the fix.** The tab bar is not up while the actions are.
    ///
    /// The old bar was hosted in `.safeAreaBar(edge: .bottom)` *above* an untouched tab
    /// bar, so the bottom of the screen carried a full-bleed grey slab sitting on a rounded
    /// glass pill: two bars, of two shapes, neither of which looked like the other. While a
    /// selection is running the bottom of the screen is not for navigating away — it is for
    /// acting on what was picked — which is why Photos, Files and Mail all take the tab bar
    /// down for the duration and put it back on the way out.
    ///
    /// Mutation-checked: putting the two back together — deleting the tab-bar branch, or
    /// hiding it on something other than the selection — fails here by name.
    @Test("The tab bar is hidden for exactly as long as the selection chrome is up")
    func theTabBarIsNotUpWhileTheActionsAre() throws {
        let anchor = "for: .tabBar"
        let found = try #require(
            Self.view.range(of: anchor),
            """
            Nothing in `LibraryView` decides the tab bar's visibility, so the selection's \
            actions are drawn in a bar stacked above it — which is the two-bottom-bars \
            defect this change exists to remove. The selection chrome replaces the tab bar; \
            it does not sit on top of it.
            """
        )

        // The one statement that carries the anchor, not the whole file and not a window of
        // characters before it: a `.hidden` somewhere else and a `selection.isActive`
        // somewhere else again would satisfy a file-wide search while leaving the tab bar
        // up, and a fixed-width window reaches the modifier on the line above — which is
        // `navigationBarTitleDisplayMode(selection.isActive ? …)` and would lend this
        // assertion the very word it is looking for. So: from the `.toolbar(` that opens
        // the statement to the anchor inside it.
        let before = String(Self.view[..<found.lowerBound])
        let opening = try #require(
            before.range(of: ".toolbar(", options: .backwards),
            "`for: .tabBar` is not inside a `.toolbar(_:for:)` call, so nothing reads it"
        )
        let statement = String(before[opening.upperBound...])
        #expect(
            statement.contains(".hidden"),
            """
            The tab bar's visibility is decided in `LibraryView`, and never set to \
            `.hidden`. The selection's actions would be drawn above a tab bar that is \
            still there.
            """
        )
        #expect(
            statement.contains("selection.isActive"),
            """
            The tab bar is hidden by something other than the selection. It has to be \
            exactly the selection: hidden for less leaves the two bars stacked, and hidden \
            for more takes a reader's way between destinations away while they are only \
            browsing.
            """
        )

        // The bar itself is up on the same condition, so the two cannot come apart.
        #expect(
            Self.view.contains("if selection.isActive {"),
            "the actions are shown on some other condition than the one hiding the tab bar"
        )
    }

    /// The count moved to the navigation bar, and left the bottom bar.
    ///
    /// Both halves, because the first is satisfiable by drawing the count twice.
    @Test("The count is the navigation title, and is no longer a label in the bar")
    func theCountIsTheNavigationTitle() {
        #expect(
            Self.view.contains("library.selected"),
            """
            The navigation bar does not state the selection, so the count has nowhere to \
            live but a label inside the bottom bar — which is the shape being replaced.
            """
        )
        #expect(
            Self.view.contains("navigationTitle"),
            "the selection state is looked up but is not the navigation title"
        )
        #expect(
            !Self.bar.contains("library.selected"),
            """
            The selection bar still carries its own count. The count is the navigation \
            title now; drawn in both places it is the same fact stated twice, and it is \
            what forced the bar to be a full-bleed slab with a left-aligned label.
            """
        )
    }

    /// The way out is the toolbar's trailing item, not an item inside the bottom bar.
    @Test("Done is a toolbar item, and is not in the selection's own bar")
    func theWayOutIsInTheToolbar() {
        #expect(
            Self.toolbar.contains("library.select.done"),
            """
            The toolbar has no way out of selection mode. A reader leaves a mode from the \
            trailing edge of the navigation bar, which is where every Apple app that has a \
            selection puts it.
            """
        )
        #expect(
            Self.toolbar.contains("selection.end()"),
            "the toolbar names a way out that does not end the selection"
        )
        #expect(
            !Self.bar.contains("library.select.done"),
            """
            The selection's bar still holds *Done*. Two ways out, in two places, and the \
            one at the bottom is the one that made this a bar rather than a set of actions.
            """
        )
        // And *Select* gives way to it rather than sitting there disabled: the mode is
        // entered and left from the same slot, which is what makes the swap read as one
        // control changing its mind rather than two controls arguing.
        #expect(
            !Self.toolbar.contains(".disabled(selection.isActive)"),
            """
            *Select* is still mounted-but-disabled while a selection runs. It is replaced \
            by *Done* now — the trailing slot is the mode's one switch — and a dead \
            *Select* beside a live *Done* is the row of half-useful controls the design \
            review objected to.
            """
        )
    }

    /// Floating chrome, at the scale the system draws floating chrome.
    ///
    /// A `Rectangle()` is the shape the defect had: full bleed, with a hard top edge that
    /// cut the captions of covers scrolling under it. Both files, because the collection
    /// and reading-list screens put the same undo bar over their own covers and a capsule
    /// on one surface beside a slab on the next is the inconsistency the owner reported.
    @Test("The chrome is an inset capsule, not a full-bleed rectangle")
    func theChromeIsAFloatingCapsule() {
        for (name, text) in [("BulkActionBar", Self.bar), ("ShelfBulkActions", Self.shelfActions)] {
            #expect(
                !text.contains("storyArcGlass(in: Rectangle())"),
                """
                \(name) still draws a full-bleed rectangle of glass. On a dark shelf that \
                reads as an opaque grey slab, and its hard top edge slices cover captions \
                in half as they scroll under it.
                """
            )
            #expect(
                text.contains("storyArcGlass(in: Capsule())"),
                """
                \(name) draws no capsule of glass. `storyArcGlass` rather than a bare \
                `glassEffect` because it is the only thing carrying the opaque fallback \
                `native-experience` requires under Reduce Transparency and Increase \
                Contrast.
                """
            )
        }
        #expect(
            Self.bar.contains(".controlSize(.large)"),
            """
            The actions are drawn at the default control size. Floating chrome has no bar \
            to sit in and has to carry its own presence — `ReaderChrome` says the same \
            thing about the reader's two buttons, and at the default size these read as \
            small pale marks over the artwork.
            """
        )
        // Grouped, so the undo capsule and the action capsule morph into one another rather
        // than stacking two edges. `DesignSystem/Glass.swift`: the container is the only
        // thing that produces that, and the modifier cannot do it from inside one surface.
        #expect(
            Self.bar.contains("GlassEffectContainer"),
            "two glass capsules are stacked without a container, so their edges do not morph"
        )
    }

    /// One action per row, named where the width allows, and named to assistive technology
    /// wherever it does not.
    ///
    /// `library-browsing`, and the review that produced it: the library's toolbar was cut
    /// from six unlabelled glyphs to two controls and two *named* menus for exactly this
    /// reason. A selection bar of three bare glyphs repeats the mistake one surface over.
    struct Action: Sendable, CustomTestStringConvertible {
        let what: String
        let key: String

        var testDescription: String { "\(what) — \(key)" }
    }

    /// The three actions the capsule carries. A table rather than three assertions, so a
    /// fourth cannot be added without editing this list.
    private static let actions: [Action] = [
        Action(what: "add to a collection or list", key: "shelves.addTo"),
        Action(what: "download", key: "library.bulk.download"),
        Action(what: "mark read", key: "library.mark.read"),
    ]

    @Test("Each action names itself in words", arguments: Self.actions)
    func eachActionIsNamed(_ action: Action) {
        #expect(
            Self.bar.contains("Text(\"\(action.key)\", bundle: .module)"),
            """
            \(action.what) does not look up `\(action.key)`, so it has no name for \
            assistive technology beyond the word "button". A `Label { Text } icon: { Image }` \
            keeps the name whatever the label style draws.
            """
        )
    }

    @Test("Each action name is translated into all four languages", arguments: Self.actions)
    func eachNameIsTranslated(_ action: Action) throws {
        for language in ["en", "fr", "de", "es"] {
            #expect(
                Self.localizations(of: action.key)[language] != nil,
                "`\(action.key)` — \(action.what) — has no \(language) translation"
            )
        }
    }

    /// And the count itself, which is a plural rather than a word.
    @Test("The count is a plural in all four languages")
    func theCountIsPluralised() throws {
        let record = Self.localizations(of: "library.selected %lld")
        for language in ["en", "fr", "de", "es"] {
            let localization = try #require(
                record[language] as? [String: Any],
                "`library.selected %lld` has no \(language) translation"
            )
            #expect(
                localization["variations"] != nil,
                """
                \(language) states the count without plural variations, so a selection of \
                one reads as a selection of several. This string is the navigation title \
                for the whole mode now.
                """
            )
        }
    }

    /// The names are drawn where there is room, and give way to glyphs only where there
    /// is not.
    ///
    /// `ViewThatFits` is what makes that a measurement rather than a guess about widths:
    /// the named row is offered first and the glyph row is the fallback, so the names are
    /// present at every size that can hold them — including the accessibility text sizes,
    /// where the fallback is doing real work and the `Label` still carries the name.
    @Test("The action names are drawn wherever the width allows")
    func theNamesAreDrawnWhereThereIsRoom() {
        #expect(
            Self.bar.contains(".labelStyle(.titleAndIcon)"),
            """
            No action in the selection's chrome draws its name. Three bare glyphs is what \
            the design review objected to in the toolbar, and this is the same mistake one \
            surface over.
            """
        )
        #expect(
            Self.bar.contains("ViewThatFits"),
            """
            The label style is fixed, so either the names are dropped at every width or \
            they overflow at the narrow ones. `ViewThatFits` offers the named row first \
            and falls back to glyphs only where the names will not fit.
            """
        )
    }

    /// Nothing picked, nothing to do — stated by the controls rather than by their absence.
    ///
    /// **Whether to show them at all was the question, and the answer is yes.** A capsule
    /// that appeared on the first pick would be floating chrome arriving under a thumb
    /// that is mid-tap, and it would change the shelf's bottom inset in the middle of a
    /// scroll. Shown and inert, it says what the mode is *for* before anything is picked;
    /// the way out is in the navigation bar throughout, so an inert capsule strands nobody.
    @Test("The actions are inert at nought picked and live above it")
    func theActionsAreDisabledAtNought() {
        #expect(
            Self.bar.contains(".disabled(selection.ids.isEmpty)"),
            """
            The actions are live with nothing picked. Each would silently do nothing, and \
            the download would put up a confirmation naming nought items.
            """
        )
        // The way out is not inside that `.disabled`, which is the mistake the old bar
        // avoided by grouping only the three: it is in the toolbar now, and the toolbar
        // does not know what is picked.
        #expect(
            !Self.toolbar.contains("selection.ids.isEmpty"),
            "the way out of the mode is gated on what is picked, which strands a reader who picked nothing"
        )
    }

    /// The library's string catalogue, for one key.
    private static func localizations(of key: String) -> [String: Any] {
        let catalogue = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/LibraryFeature/Resources/Localizable.xcstrings")
        guard
            let data = try? Data(contentsOf: catalogue),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = parsed["strings"] as? [String: Any],
            let record = strings[key] as? [String: Any]
        else {
            fatalError("the library's string catalogue is not readable at \(catalogue.path)")
        }
        return record["localizations"] as? [String: Any] ?? [:]
    }
}
