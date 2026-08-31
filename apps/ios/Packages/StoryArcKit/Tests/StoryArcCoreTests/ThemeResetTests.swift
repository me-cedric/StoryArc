import Testing

internal import StoryArcCore

/// That resetting a modified preset restores that preset, and nothing else.
///
/// `reading-themes`, *The reset names what it restores*:
///
/// > **THEN** the action names that preset — the reader who modified Calm is offered Calm
/// > back, not an unnamed default
/// > **AND** every axis returns to that preset's published value, including any the reader
/// > never touched
/// > **AND** the other five presets, the custom colour slot, the per-series memory and the
/// > global default are unchanged, because a reset is not a factory reset
///
/// **The custom-slot clause is the one that failed.** `restored()` was written as
/// `ReadingTheme(preset: preset)`, which is `adopting(_:)`'s body — and `adopting` drops the
/// custom palette *on purpose*, because tapping one of the six is how a reader leaves their
/// own colours. A reset is not that act. A reader who had made a palette, chosen Calm, and
/// nudged the line spacing lost the palette by putting the line spacing back.
///
/// Android mirrors this suite in `ThemeResetTest`, case for case.
@Suite("A reset restores the preset, not the factory")
struct ThemeResetTests {

    /// A palette the reader made, distinguishable from anything a preset would produce.
    private let mine = ReaderPalette(name: "Mine", background: "#123456", foreground: "#FEDCBA")

    @Test("Every axis returns to the preset's own values, including untouched ones")
    func everyAxisReturns() {
        let modified = ReadingTheme(preset: .calm, deviations: [.lineSpacing, .margins])

        let reset = modified.restored()

        #expect(reset.preset == .calm, "the reset restores the preset the reader was on")
        #expect(reset.deviations.isEmpty, "no axis is left deviating, touched or not")
        #expect(!reset.isModified)
    }

    @Test("The custom colour slot survives, because a reset is not a factory reset")
    func theCustomSlotSurvives() {
        let modified = ReadingTheme(
            preset: .calm,
            deviations: [.lineSpacing],
            custom: mine
        )

        let reset = modified.restored()

        #expect(
            reset.custom == mine,
            """
            The reset discarded the reader's own palette. `reading-themes` lists the custom \
            colour slot among the things a reset leaves alone: "a reset is not a factory \
            reset". Dropping it is `adopting(_:)`'s behaviour, and that is a different act — \
            tapping one of the six presets is how a reader leaves their own colours.
            """
        )
    }

    @Test("A preset with nothing deviating is already restored, and says so")
    func anUnmodifiedPresetIsUnchanged() {
        for preset in ThemePreset.allCases {
            let clean = ReadingTheme(preset: preset, custom: mine)

            #expect(
                !clean.isModified,
                """
                \(preset) with no deviations reports itself modified, so the reset action \
                would be offered for it. `reading-themes`: the action is "absent rather than \
                present and doing nothing, because a control that never changes anything \
                teaches a reader to distrust the ones that do".
                """
            )
            #expect(clean.restored() == clean, "restoring it changes nothing")
        }
    }

    @Test("Restoring one preset says nothing about the other five")
    func theOtherPresetsAreUntouched() {
        // The type holds one preset, so "the other five are unchanged" is a property of what
        // the reset *is*: a value returned, not a store rewritten. Asserted as the absence of
        // any other preset in the result, which is the only form the claim can take here.
        let reset = ReadingTheme(preset: .calm, deviations: [.margins]).restored()

        #expect(reset.preset == .calm)
        for other in ThemePreset.allCases where other != .calm {
            #expect(reset.preset != other)
        }
    }

    @Test("Adopting a preset still drops the custom palette, which is a different act")
    func adoptingIsNotResetting() {
        let mineInForce = ReadingTheme(preset: .calm, deviations: [.margins], custom: mine)

        #expect(
            mineInForce.adopting(.paper).custom == nil,
            """
            Tapping one of the six presets must still leave the reader's own colours behind — \
            `reading-themes` says a preset applies "every axis the preset defines ... at \
            once", and a preset that kept a custom background would not be the preset that \
            was tapped. This is the distinction the reset fix must not blur.
            """
        )
    }
}
