import Testing

import StoryArcCore
@testable import SettingsFeature

/// `reading-themes`, *Changing the global default*: a default change must not erase the
/// other fields of the stored default. Before this, `choose(_:for:)` wrote a fresh
/// `ShelfSettings(theme:values:)`, which put the transition, the adjustments and the matte
/// back to their built-in values on every preset tap.
@MainActor
@Suite("Changing a reading default keeps the rest of the stored value")
struct ReadingDefaultsChoosingTests {

    @Test("The chosen preset and its typography land, and nothing else moves")
    func onlyThePresetAndItsTypographyChange() {
        var existing = ShelfSettings(theme: ReadingTheme(preset: .paper))
        existing.transition = .pageCurl
        existing.offsetsSpreads = true
        existing.showsPageSeparator = true
        existing.fit = .width

        let updated = ReadingDefaults.choosing(.calm, from: existing)

        #expect(updated.theme.preset == .calm, "the chosen preset did not land")
        #expect(updated.values == ThemePreset.calm.values, "the chosen preset's typography did not land")
        #expect(
            updated.transition == .pageCurl && updated.offsetsSpreads && updated.showsPageSeparator
                && updated.fit == .width,
            """
            Choosing a preset moved a field it was never asked to touch. Before this, a fresh \
            `ShelfSettings(theme:values:)` put the transition, the spread offset, the \
            separator and the fit back to their built-in values on every tap.
            """
        )
    }

    @Test("The new preset drops any deviation and any custom colour the old one carried")
    func thePresetItselfIsReplacedWhole() {
        var existing = ShelfSettings(theme: ReadingTheme(preset: .paper))
        existing.theme = existing.theme.deviating(on: .lineSpacing)

        let updated = ReadingDefaults.choosing(.calm, from: existing)

        #expect(
            !updated.theme.isModified,
            "The new preset must start clean: `ReadingTheme(preset:)` is what `adopting` uses too."
        )
    }
}
