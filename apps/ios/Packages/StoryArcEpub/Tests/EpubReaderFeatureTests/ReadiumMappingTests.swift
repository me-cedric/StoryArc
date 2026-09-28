import Testing

import ReadiumNavigator
import StoryArcCore
@testable import EpubReaderFeature

/// What reaches Readium.
///
/// The domain decides what a theme *is*; this is the only place that knows what
/// Readium calls each part, so it is the only place a rename or an inert preference
/// can hide. Runs on a simulator because `EPUBPreferences` is Readium's, and Readium
/// is iOS-only — which is why this package exists.
@Suite("Readium mapping")
struct ReadiumMappingTests {

    @Test("Original overrides size, family, weight and margins, and leaves the rest to the publisher")
    func original() {
        let theme = ReadingTheme(preset: .original)
        var values = theme.preset.values
        values.fontSize = .large
        values.pageMargins = 2.1
        // Original's own default is `.publisher`, whose `readium` mapping is nil by
        // design — "leaves the publication's own family in place". A reader who has
        // moved the axis holds a real face, which is the case this asserts.
        values.typeface = .serif

        let preferences = theme.preferences(values: values)

        #expect(preferences.publisherStyles == true)
        #expect(preferences.fontSize == FontSizeStep.large.fraction)
        // `ThemeAxis.requiresPublisherStylesOff` says these three reach the page
        // regardless of `publisherStyles`, same as font size above.
        #expect(preferences.fontFamily != nil)
        #expect(preferences.pageMargins == 2.1)
        // Everything the publisher styles: untouched, not set to a default.
        #expect(preferences.backgroundColor == nil)
        #expect(preferences.textColor == nil)
        #expect(preferences.hyphens == nil)
        #expect(preferences.lineHeight == nil)
        #expect(preferences.textAlign == nil)
    }

    @Test("Bold raises the weight under Original too")
    func boldAppliesUnderOriginal() {
        var values = ThemePreset.original.values
        values.isBold = true
        let theme = ReadingTheme(preset: .original)

        let preferences = theme.preferences(values: values)

        #expect(
            preferences.fontWeight != nil,
            """
            Bold did nothing under Original. `boldText` is in the `false` half of \
            `ThemeAxis.requiresPublisherStylesOff`, so the control was live while it \
            changed nothing on the page — the defect `reading-themes`'s publisher-styles \
            scenario forbids for a control that is shown as usable.
            """
        )
    }

    @Test("Every other preset takes over, with colours from the tokens")
    func overridingPresets() {
        for preset in ThemePreset.allCases where preset != .original {
            let theme = ReadingTheme(preset: preset)
            let preferences = theme.preferences(values: preset.values)

            #expect(preferences.publisherStyles == false, "\(preset) should override")
            #expect(preferences.backgroundColor != nil, "\(preset) needs a background")
            #expect(preferences.textColor != nil, "\(preset) needs a text colour")
            #expect(preferences.fontFamily != nil, "\(preset) chooses a face")
            #expect(preferences.lineHeight == preset.values.lineHeight)
            #expect(preferences.pageMargins == preset.values.pageMargins)
        }
    }

    @Test("The colours are the token colours, parsed rather than approximated")
    func coloursComeFromTokens() {
        let theme = ReadingTheme(preset: .paper)
        let preferences = theme.preferences(values: theme.preset.values)

        // Same hex string the preset swatch draws, so the card and the page cannot
        // show different colours.
        #expect(preferences.backgroundColor == ReadiumNavigator.Color(hex: theme.background))
        #expect(preferences.textColor == ReadiumNavigator.Color(hex: theme.foreground))

        // `Color(hex:)` is failable, so a token the parser rejects satisfies both
        // comparisons above with a pair of nils. These two say it parsed, which is what
        // makes the comparisons mean anything. `theme.background` is not optional, so the
        // `#require` that stood here could not fail and said nothing.
        #expect(preferences.backgroundColor != nil, "the background token must parse as a colour")
        #expect(preferences.textColor != nil, "the text token must parse as a colour")
    }

    @Test("Bold raises the weight without changing the family")
    func boldIsAWeight() {
        let bold = ReadingTheme(preset: .bold)
        let plain = ReadingTheme(preset: .paper)

        let boldPreferences = bold.preferences(values: bold.preset.values)
        let plainPreferences = plain.preferences(values: plain.preset.values)

        #expect(boldPreferences.fontWeight != nil)
        // `reading-themes`: bold "raises weight without changing family".
        #expect(plainPreferences.fontWeight == nil)
    }

    @Test("A moved axis reaches Readium, and the preset stays selected")
    func deviationApplies() {
        var values = ThemePreset.paper.values
        values.lineHeight = 2.4

        let theme = ReadingTheme(preset: .paper).deviating(on: .lineSpacing)
        let preferences = theme.preferences(values: values)

        #expect(preferences.lineHeight == 2.4)
        #expect(theme.preset == .paper)
        #expect(theme.isModified)
    }
}
