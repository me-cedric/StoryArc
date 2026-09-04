import Foundation
import Testing

@testable import LibraryFeature

/// What the selection mode's actions are **called**, in four languages.
///
/// Split from ``BulkSelectionChromeTests`` when that file crossed SwiftLint's 400-line cap.
/// The seam is a real one rather than a place to cut: everything here is about words — the key
/// each action looks up, and whether the catalogue answers it in every shipped language — and
/// everything left there is about shape and state. The two halves share no assertion; they
/// share ``LibraryFeatureSource``.
///
/// **Why these read source text rather than composing a view.** `swift test` runs on the host
/// with no window, so a name drawn on screen is not a thing this process can see. What it can
/// see is that the lookup exists and that the catalogue answers it. The frames in
/// `docs/designs/screenshots/ios-selection-chrome-2026-09-04/` are the other half, and the
/// reason both are required: the tier a phone actually draws went wrong for days while every
/// assertion here passed.
@Suite("The selection's actions are named, in four languages")
struct BulkSelectionNamesTests {

    private static let bar =
        LibraryFeatureSource.code(of: "Sources/LibraryFeature/BulkActionBar.swift")

    /// One action per row, named where the width allows, and named to assistive technology
    /// wherever it does not.
    ///
    /// `library-browsing`, and the review that produced it: the library's toolbar was cut
    /// from six unlabelled glyphs to two controls and two *named* menus for exactly this
    /// reason. A selection bar of three bare glyphs repeats the mistake one surface over.
    struct Action: Sendable, CustomTestStringConvertible {
        let what: String
        let key: String
        /// Which source holds the lookup — the capsule, or the menu the capsule opens.
        let source: String

        var testDescription: String { "\(what) — \(key)" }
    }

    private static let addToMenu =
        LibraryFeatureSource.code(of: "Sources/LibraryFeature/AddToShelfMenu.swift")

    /// Every action the mode offers, and where its name is looked up. A table rather than
    /// separate assertions, so a fifth cannot be added without editing this list.
    ///
    /// **`shelves.addTo` moved, and it moved for the reason the row exists.** It used to be
    /// the capsule's first control, drawn as `text.badge.plus` — a glyph Apple uses only as a
    /// named row inside a menu, for an action that opens a chooser rather than doing
    /// something. It is now inside the overflow, so its name is looked up where it is drawn.
    /// Asserting it against the capsule after that move would have been asserting a lookup
    /// kept alive to satisfy a test.
    private static let actions: [Action] = [
        Action(what: "add to a collection or list", key: "shelves.addTo", source: "menu"),
        Action(what: "download", key: "library.bulk.download", source: "bar"),
        Action(what: "mark read", key: "library.mark.read", source: "bar"),
        Action(what: "the overflow itself", key: "detail.more", source: "bar"),
    ]

    @Test("Each action names itself in words", arguments: Self.actions)
    func eachActionIsNamed(_ action: Action) {
        let source = action.source == "bar" ? Self.bar : Self.addToMenu
        #expect(
            source.contains("Text(\"\(action.key)\", bundle: .module)")
                || source.contains("\"\(action.key)\", bundle: .module"),
            """
            \(action.what) does not look up `\(action.key)` in the \(action.source), so it \
            has no name for assistive technology beyond the word "button". A \
            `Label { Text } icon: { Image }` keeps the name whatever the label style draws.
            """
        )
    }

    @Test("Each action name is translated into all four languages", arguments: Self.actions)
    func eachNameIsTranslated(_ action: Action) throws {
        for language in ["en", "fr", "de", "es"] {
            #expect(
                LibraryFeatureSource.localizations(of: action.key)[language] != nil,
                "`\(action.key)` — \(action.what) — has no \(language) translation"
            )
        }
    }

    /// And the count itself, which is a plural rather than a word.
    @Test("The count is a plural in all four languages")
    func theCountIsPluralised() throws {
        let record = LibraryFeatureSource.localizations(of: "library.selected %lld")
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
}
