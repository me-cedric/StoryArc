import Foundation
import Testing

/// The reader's menu does not draw its words in the accent, on a material the page tints.
///
/// `quiet-reader` moved eleven controls off the page and **into** this sheet, so it is now
/// where a reader goes to change anything about how a publication is drawn. The September
/// sweep photographed what they find there: *Contents*, *Appearance* and *Transition* all
/// purple, because a `Button` in a `List` draws its label in the environment's tint and
/// `ThemeResolver` sets that tint to `theme.accent` — see `AccentReachesTheControlsTests`,
/// which is the rule this one is the other half of.
///
/// **The tint is right for a control and wrong for a word here, and the reason is the
/// ground.** The sheet is presented at `.medium` with
/// `presentationBackgroundInteraction`, so the page shows through it: over the salmon page
/// in `ios-comic-reader-menu.png` the material is warm brown and the purple labels sit on
/// it at low contrast. `DesignSystem/Glass.swift` had already written down why a fixed
/// colour cannot be put on a surface whose luminance is whatever is scrolling past —
/// "inventing a token would be certifying a surface whose ground is unknowable" — and
/// ``storyArcGlassText(_:)`` is the answer it reached. The accent is a fixed colour like
/// any other.
///
/// So two spellings hold the whole rule, and both are on the `List` rather than on each
/// row: `.buttonStyle(.plain)` is what stops a row's label taking the tint at all, and
/// `.storyArcGlassText` is what the text that is left states instead. Per-row styling was
/// the alternative and it is the shape this defect already has once — `GlassIsUntintedTests`
/// exists because a rule written in one file was reintroduced at five call sites that never
/// opened it.
///
/// The accent is not banished from the sheet. It still draws the page slider, the toggles,
/// both pickers' values, the coarse fill behind the contents row and the *Done* action in
/// the navigation bar — which has a glass pill of its own for a ground and is the one
/// control the platform expects to be tinted.
///
/// **This reads source text**, the same trade `GlassIsUntintedTests` and
/// `AccentReachesTheControlsTests` make and explain: composing these views needs a
/// simulator and `swift test` runs on the host. It cannot see a rendered pixel; it can see
/// the modifier that made the pixel wrong.
@Suite("The reader's menu is legible on a page-tinted material")
struct ReaderMenuOnGlassTests {

    /// The package directory, from this test's own compiled path.
    ///
    /// `#filePath` and not a walk up from the working directory: this repository nests agent
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs looking for a marker
    /// leaves the checkout under test and guards the parent's copy.
    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ReaderFeatureTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // StoryArcKit

    /// One reader's menu, and where its source lives.
    private struct Menu {
        let reader: String
        let path: String
    }

    /// Both readers, because `ReaderMenuEntry` gives them one menu and the sweep
    /// photographed the same purple in both — `ios-comic-reader-menu.png` and
    /// `ios-epub-reader-menu.png`.
    private static let menus: [Menu] = [
        Menu(reader: "The comic reader", path: "Sources/ReaderFeature/ReaderMenu.swift"),
        Menu(
            reader: "The reflowable reader",
            path: "../StoryArcEpub/Sources/EpubReaderFeature/EpubReaderMenu.swift"
        ),
    ]

    /// The rest of what the two menus are built from.
    ///
    /// The position line under each contents row, and the comic reader's settings section —
    /// which states a one-line reason under a transition this device refuses. The reflowable
    /// reader's line is the one that carried a **fixed** colour rather than the tint:
    /// `theme.palette.textSecondary`, which is the exact thing `Glass.swift`'s second
    /// paragraph was written about.
    private static let menuParts: [Menu] = [
        Menu(
            reader: "The comic reader",
            path: "Sources/ReaderFeature/ReaderMenuProgress.swift"
        ),
        Menu(
            reader: "The comic reader",
            path: "Sources/ReaderFeature/ReaderMenuSettings.swift"
        ),
        Menu(
            reader: "The reflowable reader",
            path: "../StoryArcEpub/Sources/EpubReaderFeature/EpubReaderProgress.swift"
        ),
    ]

    /// A file's code with its `//` prose removed.
    ///
    /// This codebase argues with itself at length in comments, and every spelling below is
    /// also quoted in the paragraphs around it.
    private func code(of path: String) throws -> String {
        let file = Self.package.appending(path: path)
        let text = try #require(
            try? String(contentsOf: file, encoding: .utf8),
            "\(file.path) could not be read — has the reader's menu moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    @Test("Neither menu draws its rows in the environment tint")
    func noMenuRowTakesTheTint() throws {
        for menu in Self.menus {
            let source = try code(of: menu.path)
            #expect(
                source.contains(".buttonStyle(.plain)"),
                """
                \(menu.reader)'s menu no longer sets `.buttonStyle(.plain)` on its list, so \
                every row is a `Button` drawing its label in the environment's tint — which \
                `ThemeResolver` sets to `theme.accent`. The sheet is presented at `.medium` \
                over the page, so that accent lands on a material tinted by whatever the \
                reader is looking at. `ios-comic-reader-menu.png` is the picture of it.
                """
            )
        }
    }

    @Test("Both menus state their foreground with the tool for text on glass")
    func bothMenusUseTheGlassText() throws {
        for menu in Self.menus + Self.menuParts {
            let source = try code(of: menu.path)
            #expect(
                source.contains(".storyArcGlassText("),
                """
                \(menu.reader)'s `\(menu.path)` no longer uses `storyArcGlassText`. That \
                modifier is the app's answer to text on a surface whose ground is unknowable: \
                a hierarchical style while the material is live, and the palette's own \
                neutral under Reduce Transparency or Increase Contrast, where the ground \
                becomes `surfaceOverlay` and is knowable again. A fixed `theme.palette` \
                colour cannot follow a material and neither can the accent.
                """
            )
        }
    }

    /// The position line is not a fixed palette colour any more.
    ///
    /// Narrower than the rule above and worth its own failure: the reflowable reader's line
    /// read `theme.palette.textSecondary` on a material that picks up the page, which is the
    /// case `Glass.swift` documents from a booted device — "in light mode the scan summary
    /// was dark grey over glass that had picked up a dark purple cover, and very nearly
    /// invisible".
    @Test("No menu line pins a palette colour onto the material")
    func noMenuLinePinsAPaletteColour() throws {
        for menu in Self.menus + Self.menuParts {
            let source = try code(of: menu.path)
            #expect(
                !source.contains(".foregroundStyle(theme.palette.text"),
                """
                \(menu.path) puts a `theme.palette` text colour on the menu's material. \
                That colour is a constant and the material's luminance is not — it is \
                whatever page is behind the sheet. `storyArcGlassText(_:)` is the modifier \
                that resolves against the material instead, and it carries the opaque \
                fallback with it.
                """
            )
        }
    }
}
