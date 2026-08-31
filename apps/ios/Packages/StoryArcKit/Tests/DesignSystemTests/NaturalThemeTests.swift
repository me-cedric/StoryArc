import SwiftUI
import Testing

@testable import DesignSystem
import StoryArcCore

/// Natural, which is a second axis rather than a fifth appearance.
///
/// `AppearanceModeTests` already asserts what Natural is *not* — a case in
/// `AppearanceMode`. This asserts what it is: an independent switch that crosses the
/// polarity it sits beside, with one appearance that declines it. Android's
/// `NaturalThemeTest` asserts the same table.
@Suite("Natural theme")
struct NaturalThemeTests {
    @Test("Natural crosses light and dark rather than replacing either")
    func naturalCarriesBothVariants() {
        // The whole reason it is not an `AppearanceMode` case: choosing it does not
        // cost the reader their choice of polarity.
        #expect(Palette.resolved(for: .light, natural: true) == .naturalLight)
        #expect(Palette.resolved(for: .dark, natural: true) == .naturalDark)
        #expect(Palette.naturalLight != Palette.naturalDark)
    }

    @Test("Off, Natural changes nothing")
    func offIsTheSameAppAsBefore() {
        #expect(Palette.resolved(for: .light, natural: false) == .light)
        #expect(Palette.resolved(for: .dark, natural: false) == .dark)
    }

    @Test("Natural follows System, Light and Dark alike")
    func naturalAppliesUnderEveryPolarity() {
        for appearance in [AppearanceMode.system, .light, .dark] {
            #expect(NaturalTheme.isAvailable(under: appearance), "\(appearance)")
            #expect(
                Palette.resolved(for: .dark, appearance: appearance, natural: true) == .naturalDark,
                "\(appearance)"
            )
        }
    }

    @Test("OLED Dark declines Natural, because true black is why it exists")
    func oledDarkKeepsItsBlackPoint() {
        // Warm cream stock and true black are opposite asks. The appearance that made a
        // promise about the black point keeps it, and the switch says why rather than
        // sitting there doing nothing.
        #expect(!NaturalTheme.isAvailable(under: .oledDark))
        #expect(!NaturalTheme.applies(true, under: .oledDark))
        #expect(Palette.resolved(for: .dark, appearance: .oledDark, natural: true) == .oledDark)
        #expect(AppearanceMode.oledDark.naturalUnavailableKey != nil)
    }

    @Test("Every other appearance offers Natural without an excuse")
    func onlyOledExplainsItself() {
        for appearance in AppearanceMode.allCases where appearance != .oledDark {
            #expect(appearance.naturalUnavailableKey == nil, "\(appearance)")
        }
    }

    @Test("Natural's accents are clay, and they follow the same rule ember does")
    func accentsAreEarthier() {
        // `design.md`: Natural's accents reach the whole app, "so the theme is coherent
        // rather than bolted onto the reader". Earthier than ember, and the light
        // variant takes the stronger one for the reason light takes `emberStrong` —
        // clay at 66 % lightness does not clear 3:1 on warm paper. `pnpm tokens:check`
        // gates both pairs.
        #expect(Palette.naturalLight.accent == StoryArcColor.Brand.clayStrong)
        #expect(Palette.naturalDark.accent == StoryArcColor.Brand.clay)
        #expect(Palette.naturalLight.accent != Palette.light.accent)
        #expect(Palette.naturalDark.accent != Palette.dark.accent)
    }

    @Test("Natural's reader surface is its own, and is not the canvas")
    func readerSurfaceIsDistinct() {
        // The surface the grain is drawn over. It is a colour in the tokens, so the
        // palette holds whether or not the texture is drawn.
        #expect(Palette.naturalLight.surfaceReader == StoryArcColor.NaturalLight.surfaceReader)
        #expect(Palette.naturalDark.surfaceReader == StoryArcColor.NaturalDark.surfaceReader)
        #expect(Palette.naturalLight.surfaceReader != Palette.naturalLight.surfaceCanvas)
        #expect(Palette.naturalDark.surfaceReader != Palette.naturalDark.surfaceCanvas)
    }

    @Test("Increase Contrast reaches Natural the way it reaches every other palette")
    func increasedContrastStrengthensNaturalToo() {
        let increased = Palette.resolved(for: .light, natural: true, contrast: .increased)

        #expect(increased.borderSubtle == Palette.naturalLight.borderStrong)
        #expect(increased.textTertiary == Palette.naturalLight.textSecondary)
    }

    @Test("The stored key is one constant, so the screen and the resolver cannot disagree")
    func storageKeyIsShared() {
        // Written by Settings › Appearance, read by `ThemeResolver`. Two literals would
        // be a switch that silently stopped doing anything.
        #expect(NaturalTheme.storageKey == "storyarc.appearance.natural")
    }
}
