import SwiftUI
import Testing

@testable import DesignSystem
import StoryArcCore

/// The token *values* are gated by `pnpm tokens:check`, which runs the WCAG
/// maths on the source of truth. These tests guard the layer above: that the
/// Swift side wires the right generated token into the right role.
@Suite("Palette wiring")
struct PaletteTests {
    @Test("Dark and light resolve to different palettes")
    func schemesDiffer() {
        #expect(Palette.resolved(for: .dark) == .dark)
        #expect(Palette.resolved(for: .light) == .light)
        #expect(Palette.dark != Palette.light)
    }

    @Test("One accent serves every appearance, which is why the violet was chosen")
    func oneAccentServesBothAppearances() {
        // The accent this replaced was a *pair*: a stronger light variant existed only
        // because the lighter one did not clear 3:1 on paper. The pink at the mark's
        // first arc stop is the same story — 7.24:1 on dark and 2.48:1 on light — and it
        // is the reason the accent is the violet from the middle of the arc instead.
        // `brand.accent` clears the floor on both canvases, 4.06 dark and 4.43 light, so
        // there is one token and deliberately no light-only twin.
        //
        // `pnpm tokens:check` gates both readings. This guards the layer above: that
        // nothing quietly reintroduces a second accent for one appearance.
        #expect(Palette.dark.accent == StoryArcColor.Brand.accent)
        #expect(Palette.light.accent == StoryArcColor.Brand.accent)
        #expect(Palette.oledDark.accent == StoryArcColor.Brand.accent)
    }

    @Test("Increase Contrast strengthens the border and the weakest text tier")
    func increasedContrastStrengthens() {
        // `native-experience`: with the setting on, "borders are strengthened". The
        // strengthening happens in the tokens, so a view that draws `borderSubtle`
        // gets it without knowing the setting exists.
        let standard = Palette.resolved(for: .dark)
        let increased = Palette.resolved(for: .dark, contrast: .increased)

        #expect(standard.borderSubtle != standard.borderStrong)
        #expect(increased.borderSubtle == standard.borderStrong)
        #expect(increased.textTertiary == standard.textSecondary)
    }

    @Test("Increase Contrast keeps a hierarchy to strengthen")
    func increasedContrastKeepsTiers() {
        // Promoting every tier would leave one tier. Primary still reads as primary.
        let increased = Palette.resolved(for: .light, contrast: .increased)

        #expect(increased.textPrimary != increased.textSecondary)
        #expect(increased.accent == Palette.light.accent)
    }

    @Test("Increase Contrast follows the appearance rather than replacing it")
    func increasedContrastKeepsAppearance() {
        let increased = Palette.resolved(for: .dark, appearance: .oledDark, contrast: .increased)

        #expect(increased.surfaceCanvas == Palette.oledDark.surfaceCanvas)
    }

    @Test("The reader surface is not the canvas surface")
    func readerSurfaceIsDistinct() {
        // Deliberate: the reader goes deeper than the app background so the page
        // is the brightest thing on screen.
        #expect(Palette.dark.surfaceReader != Palette.dark.surfaceCanvas)
        #expect(Palette.light.surfaceReader != Palette.light.surfaceCanvas)
    }
}

@Suite("Theme accent resolution")
struct ThemeTests {
    @Test("With no cover accent the theme falls back to the palette accent")
    func fallsBackToBrand() {
        let theme = Theme(palette: .dark)

        #expect(theme.accent == Palette.dark.accent)
    }

    @Test("A cover accent overrides the brand accent for its subtree")
    func coverAccentWins() {
        let theme = Theme(palette: .dark, coverAccent: StoryArcColor.Brand.secondary)

        #expect(theme.accent == StoryArcColor.Brand.secondary)
    }
}

/// What an appearance resolves to.
///
/// `settings-and-about` names four and is specific about the one that is not what its
/// name implies: OLED Dark makes chrome true black and deliberately does *not* make the
/// reader surface true black. Android's `AppearanceTest` asserts the same table.
@Suite("Appearance mode")
struct AppearanceModeTests {
    @Test("System defers to the platform, the others force a scheme")
    func colorSchemeMapping() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
        #expect(AppearanceMode.oledDark.colorScheme == .dark)
    }

    @Test("Every mode is offered, and System is the documented default")
    func allCases() {
        #expect(AppearanceMode.allCases.count == 4)
        #expect(AppearanceMode(rawValue: "system") == .system)
        #expect(AppearanceMode.allCases.first == .system)
        // Natural is "a theme rather than an appearance" and carries its own light and
        // dark variants, so putting it here would force a choice the spec avoids.
        #expect(!AppearanceMode.allCases.contains { $0.rawValue.contains("natural") })
    }

    @Test("A linked reading theme follows the appearance, and OLED Dark does not go darker")
    func linkedThemeMapping() {
        #expect(ThemePreset.matching(.light) == .paper)
        #expect(ThemePreset.matching(.dark) == .quiet)
        // The difference between Dark and OLED Dark is the *chrome*'s black point, and a
        // reading surface is deliberately never pure black — so a darker reading theme
        // here would undo the reason that appearance exists.
        #expect(ThemePreset.matching(.oledDark) == .quiet)
        // System is a question rather than a value, and the caller is meant to resolve it.
        #expect(ThemePreset.matching(.system) == .paper)
    }

    @Test("OLED Dark makes chrome true black and the reader surface deliberately not")
    func oledKeepsTheReaderOffBlack() {
        // The whole point of the scenario: pure black smears on OLED during a page turn,
        // which is the exact motion this app is built around.
        let palette = Palette.oledDark
        #expect(palette.surfaceCanvas != palette.surfaceReader)
        #expect(palette.surfaceCanvas == StoryArcColor.OledDark.surfaceCanvas)
        #expect(palette.surfaceReader == StoryArcColor.OledDark.surfaceReader)
    }

    @Test("OLED Dark wins over the resolved scheme, because it is an explicit choice")
    func oledOverridesTheScheme() {
        #expect(Palette.resolved(for: .light, appearance: .oledDark) == .oledDark)
        #expect(Palette.resolved(for: .dark, appearance: .oledDark) == .oledDark)
        // And the others still follow the scheme they were given.
        #expect(Palette.resolved(for: .dark, appearance: .system) == .dark)
        #expect(Palette.resolved(for: .light, appearance: .system) == .light)
    }

    @Test("Only the appearance that is not what its name implies carries a note")
    func onlyOledExplainsItself() {
        // `settings-and-about`: honoured where it helps and *explained* where it does
        // not. An explanation on the other three would be noise.
        #expect(AppearanceMode.oledDark.localizedNoteKey != nil)
        for mode in AppearanceMode.allCases where mode != .oledDark {
            #expect(mode.localizedNoteKey == nil, "\(mode)")
        }
    }
}

@Suite("Type roles")
struct TypographyTests {
    @Test("Display is the only serif role — the app has exactly one typographic voice")
    func onlyDisplayIsSerif() {
        let serifRoles = TextRole.allCases.filter(\.usesEditorialSerif)

        #expect(serifRoles == [.display])
    }

    @Test("Every role carries a positive size and a line height above it")
    func metricsAreSane() {
        for role in TextRole.allCases {
            let metrics = role.metrics
            #expect(metrics.size > 0, "\(role) has a non-positive size")
            #expect(metrics.lineHeight >= metrics.size, "\(role) line height is below its size")
        }
    }

    @Test("The scale descends without a tie, so hierarchy comes from size contrast")
    func scaleDescends() {
        let ordered: [TextRole] = [.display, .title1, .title2, .title3, .headline]
        let sizes = ordered.map(\.metrics.size)

        #expect(sizes == sizes.sorted(by: >))
    }
}
