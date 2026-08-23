import SwiftUI
import Testing

@testable import DesignSystem

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

@Suite("Appearance mode")
struct AppearanceModeTests {
    @Test("System defers to the platform, the others force a scheme")
    func colorSchemeMapping() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test("Every mode is offered, and System is the documented default")
    func allCases() {
        #expect(AppearanceMode.allCases.count == 3)
        #expect(AppearanceMode(rawValue: "system") == .system)
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
