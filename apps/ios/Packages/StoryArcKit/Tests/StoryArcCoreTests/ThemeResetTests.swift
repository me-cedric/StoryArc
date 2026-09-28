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
/// **"The custom colour slot ... unchanged" is the reader's own named palette, kept in
/// `EpubReaderModel.customPalette` whether or not it is on the page — not `ReadingTheme.custom`,
/// which is only what is in force right now.** A reset drops `custom` the same as every other
/// axis, which is what puts the background back on the preset's own value; the slot elsewhere
/// is untouched, so the seventh card is still there afterwards.
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

    @Test("The background returns to the preset's own value, the same as any other axis")
    func theBackgroundReturnsToo() {
        let modified = ReadingTheme(
            preset: .calm,
            deviations: [.lineSpacing],
            custom: mine
        )

        let reset = modified.restored()

        #expect(
            reset.custom == nil,
            """
            The reset kept the reader's own colour in force, so the background did not \
            return to Calm's own value — the one axis "every axis returns to that preset's \
            published value" did not reach. The custom colour *slot* `reading-themes` lists \
            among the things a reset leaves alone is `EpubReaderModel.customPalette`, kept \
            whether or not it is in force; `custom` here is only what is on the page now.
            """
        )
    }

    @Test("A preset with nothing deviating is already restored, and says so")
    func anUnmodifiedPresetIsUnchanged() {
        for preset in ThemePreset.allCases {
            let clean = ReadingTheme(preset: preset)

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
