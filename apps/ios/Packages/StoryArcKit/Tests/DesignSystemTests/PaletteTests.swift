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

    @Test("Light uses the stronger accent, because ember at 70% lightness fails on paper")
    func lightUsesStrongAccent() {
        #expect(Palette.light.accent == StoryArcColor.Brand.emberStrong)
        #expect(Palette.dark.accent == StoryArcColor.Brand.ember)
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
        let theme = Theme(palette: .dark, coverAccent: StoryArcColor.Brand.ink)

        #expect(theme.accent == StoryArcColor.Brand.ink)
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
