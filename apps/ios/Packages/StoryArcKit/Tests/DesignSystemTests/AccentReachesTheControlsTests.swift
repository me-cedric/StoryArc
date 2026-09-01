import Foundation
import SwiftUI
import Testing

@testable import DesignSystem

/// The accent reaches the controls the design review said it did not.
///
/// `ArcStopsAreNotChromeTests` is the other half of this rule and stops the mark's identity
/// colours leaking *into* chrome. It cannot say that chrome has an accent at all — a guard
/// that only forbids the wrong colour is satisfied by a shelf drawn entirely in grey.
///
/// The review named four kinds: **tab bars, chips, sliders and progress ticks**. Three of the
/// four are accented on iOS by *one line*, and that is the finding worth pinning. Every
/// unstyled control on this platform draws itself in the environment's tint, so the tab bar's
/// selected item, the reader's page slider, the adjustment sliders and the determinate
/// progress views all take their colour from the single `.tint(theme.accent)` in
/// `ThemeResolver`. Nothing in the build would notice if that line went: the app would keep
/// compiling and every one of those controls would quietly return to system blue.
///
/// The fourth — progress ticks on a cover — is drawn by hand, so it is pinned by hand.
///
/// **What is deliberately not here.** iOS's segmented control, which is what plays the part
/// Android's filter chips play, is neutral by platform design and stays neutral: the only way
/// to colour its selected segment is `UISegmentedControl.appearance()`, a global UIKit proxy
/// that cannot follow the Natural theme's two accents, and `native-experience` asks this app
/// to follow the platform's own conventions rather than fight them. The picture is in
/// `docs/designs/screenshots/quieter-toolbar-2026-09-02/`.
///
/// **This reads source text**, the same trade `GlassIsUntintedTests` makes and explains: a
/// resolved `Color` cannot be compared on the host, and the thing that regresses is the
/// assignment rather than the pixel.
@Suite("The accent reaches the controls")
struct AccentReachesTheControlsTests {

    /// A source file, reached from this file rather than discovered.
    ///
    /// `#filePath`, not a walk up from the working directory: this repository nests agent
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs looking for a marker
    /// leaves the checkout under test and guards the parent's copy.
    private static func source(_ relativePath: String) -> String {
        let kit = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DesignSystemTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StoryArcKit
        let file = kit.appending(path: relativePath)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fatalError("\(relativePath) is not at \(file.path) — has it moved?")
        }
        return text
    }

    /// A file's code, with `//` prose removed.
    ///
    /// This codebase argues with itself at length in comments, and both rules below search
    /// for the exact spelling of a modifier that the prose around them also quotes.
    private static func code(of relativePath: String) -> String {
        source(relativePath)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    private static let theme = code(of: "Sources/DesignSystem/Theme.swift")
    private static let coverGrid = code(of: "Sources/LibraryFeature/CoverGrid.swift")

    /// The one line the tab bar, the sliders and every unstyled control hang off.
    ///
    /// It is applied by `ThemeResolver`, which is applied once at the root of each window and
    /// each presentation. `Theme.accent` is `coverAccent ?? palette.accent`, so this is also
    /// what makes §7 of `docs/design.md` work: inside a publication's context the same line
    /// hands down the cover-derived colour instead, with no control knowing it happened.
    @Test("The theme injects the accent as the environment tint")
    func theResolverTintsTheTree() {
        // A local rather than the expression, so a failure prints the answer instead of the
        // whole file. `#expect` dumps what it evaluated, and what it evaluated here is four
        // hundred lines of Swift.
        let tintsTheTree = Self.theme.contains(".tint(theme.accent)")
        #expect(
            tintsTheTree,
            """
            `ThemeResolver` no longer tints the tree. Every unstyled control on iOS draws \
            itself in the environment's tint, so this one line is what colours the tab bar's \
            selected item, the reader's page slider and every determinate progress view — \
            and its absence compiles, runs, and returns all of them to system blue.
            """
        )
    }

    /// A progress tick is a pair, and both halves come from the accent.
    ///
    /// The rail was `.black.opacity(0.35)` — a scrim rather than a colour, so it read as
    /// mid-grey on a pale cover and vanished on a dark one, which is the case where a reader
    /// most needs to see how much of the bar is *not* filled. `design.md` gives `accentMuted`
    /// exactly this job and nothing in the app was doing it.
    @Test("A cover's progress bar draws its fill and its rail from the accent")
    func theProgressRailIsTheAccentAtRest() {
        let railIsMuted = Self.coverGrid.contains(".fill(theme.palette.accentMuted)")
        let fillIsAccent = Self.coverGrid.contains("theme.palette.textSecondary : theme.accent")
        #expect(
            railIsMuted,
            """
            The progress rail is not `accentMuted` any more. `design.md` gives that token one \
            job — "accent at rest: progress rails, unselected indicators" — and this is the \
            only thing in the app doing it, so a rail changed back leaves the token unused \
            and the unfilled half of the bar at the mercy of whatever cover is under it.
            """
        )
        #expect(
            fillIsAccent,
            """
            The progress fill is no longer the accent. `library-browsing` asks a cover to \
            carry the reader's position and `design.md` calls the accent "your progress"; \
            the finished case is deliberately *not* the accent, because a full bar means \
            finished rather than in progress.
            """
        )
    }

    /// And the token the rail uses is a real one, so a rename breaks this file's compile
    /// rather than leaving it searching for a dead name.
    ///
    /// The same trick `ArcStopsAreNotChromeTests` uses and explains: a guard that only holds
    /// strings passes vacuously the day the thing it names is renamed.
    @Test("The rail's token is the palette's, on every appearance")
    func theRailsTokenExists() {
        let muted: [Color] = [
            Palette.dark.accentMuted,
            Palette.light.accentMuted,
            Palette.oledDark.accentMuted,
            Palette.naturalDark.accentMuted,
            Palette.naturalLight.accentMuted,
        ]
        #expect(muted.count == 5)
        // Natural carries its own accent pair, so its rail is clay rather than the violet.
        // Asserted rather than assumed: a progress bar that stayed violet under Natural would
        // be the one violet thing left on a cream page.
        #expect(Palette.naturalDark.accentMuted != Palette.dark.accentMuted)
        #expect(Palette.light.accentMuted == Palette.dark.accentMuted)
    }
}
