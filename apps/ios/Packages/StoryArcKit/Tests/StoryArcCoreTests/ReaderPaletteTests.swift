import Foundation
import Testing

@testable import StoryArcCore

/// Contrast, and the seventh colour slot.
///
/// `reading-themes` derives a text colour at 7:1 and refuses a pairing below 4.5:1
/// "with the measured ratio stated", so the arithmetic is the requirement rather than
/// a detail under it. Android's `ReadingThemeTest` asserts the same numbers.
@Suite("Reader palettes")
struct ReaderPaletteTests {

    // MARK: - Contrast

    @Test("Black on white is the extreme WCAG defines, and a colour on itself is the floor")
    func contrastBounds() {
        #expect(abs(ReadingContrast.ratio("#000000", "#FFFFFF") - 21) < 0.01)
        #expect(abs(ReadingContrast.ratio("#FFFFFF", "#000000") - 21) < 0.01)
        #expect(abs(ReadingContrast.ratio("#3A5F8A", "#3A5F8A") - 1) < 0.0001)
    }

    @Test("A colour it cannot read is the worst ratio, never the best")
    func malformedHexIsNotAPass() {
        // The failure mode that matters: a typo must not be the reason a pairing is
        // accepted, so an unreadable colour reports 1 rather than nil or 21.
        #expect(ReadingContrast.ratio("not a colour", "#FFFFFF") == 1)
        #expect(ReadingContrast.luminance(of: "#12345") == nil)
        // Three-digit hex is legal CSS and a picker may hand one over.
        #expect(abs(ReadingContrast.ratio("#fff", "#000000") - 21) < 0.01)
    }

    @Test("The runtime maths agrees with the token pipeline's, to four places")
    func agreesWithTheTokenGate() {
        // Golden values from `packages/design-tokens/scripts/oklch.mjs`, which is what
        // fails the build when a reading theme drops below 7:1. If the two drifted, a
        // pairing could pass the gate and be refused in the sheet, or worse the other
        // way round. Paper's own pair, and the mid-grey ceiling.
        #expect(abs(ReadingContrast.ratio("#F5F1EC", "#1D1A17") - 15.4044) < 0.0001)
        #expect(abs(ReadingContrast.ratio("#808080", "#000000") - 5.3172) < 0.0001)
    }

    @Test("A derived text colour is the better of black and white")
    func derivationTakesTheExtreme() {
        #expect(ReaderPalette.derived(name: "n", background: "#FFFFFF").foreground == "#000000")
        #expect(ReaderPalette.derived(name: "n", background: "#101010").foreground == "#FFFFFF")
    }

    @Test("A mid-tone background is reported as unable to reach AAA rather than dressed up")
    func midToneCannotReachAAA() {
        // Grey tops out near 5.3 against black. The honest answer is that no text
        // colour reaches 7:1 on it — silently returning black would look like a pass.
        let grey = ReaderPalette.derived(name: "grey", background: "#808080")
        #expect(grey.isReadable)
        #expect(!grey.meetsAAA)
    }

    @Test("A pairing below AA is refused, and the ratio survives to be shown")
    func illegibleOverrideIsRefusedWithItsNumber() {
        // `reading-themes` refuses below 4.5:1 "with the measured ratio stated", so
        // the attempt has to exist as a value long enough to be measured.
        let tried = ReaderPalette
            .derived(name: "n", background: "#FFFFFF")
            .overriding(foreground: "#DDDDDD")
        #expect(!tried.isReadable)
        #expect(tried.contrast > 1)
    }

    // MARK: - The seventh slot

    @Test("Custom colours sit alongside the presets and keep the typography")
    func customIsASeventhSlot() {
        let palette = ReaderPalette.derived(name: "Sea", background: "#0B2027")
        let theme = ReadingTheme(preset: .calm, deviations: [.lineSpacing]).adopting(palette)
        #expect(theme.isCustom)
        // The preset is not overwritten, and the reader's line height survives.
        #expect(theme.preset == .calm)
        #expect(theme.deviations == [.lineSpacing])
        #expect(theme.discardingCustomColours().custom == nil)
    }

    @Test("Tapping one of the six leaves the reader's own palette behind")
    func adoptingAPresetDropsTheCustomColours() {
        let theme = ReadingTheme().adopting(ReaderPalette.derived(name: "Sea", background: "#0B2027"))
        #expect(theme.adopting(ThemePreset.focus).custom == nil)
        // Not `restored()`. That line asserted the old behaviour and `reading-themes` now
        // contradicts it: a reset leaves "the custom colour slot … unchanged, because a reset
        // is not a factory reset". `ThemeResetTests` owns that clause; the two acts are
        // deliberately different and `discardingCustomColours` is how a reader drops a palette
        // on purpose.
        #expect(theme.discardingCustomColours().custom == nil)
    }

    @Test("Original refuses custom colours, because the publisher's are the point")
    func originalKeepsItsOwnColours() {
        let theme = ReadingTheme(preset: .original)
            .adopting(ReaderPalette.derived(name: "Sea", background: "#0B2027"))
        #expect(!theme.isCustom)
    }
}
