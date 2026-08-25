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

    @Test("Original leaves the publisher in charge and overrides only size")
    func original() {
        let theme = ReadingTheme(preset: .original)
        var values = theme.preset.values
        values.fontSize = .large

        let preferences = theme.preferences(values: values)

        #expect(preferences.publisherStyles == true)
        #expect(preferences.fontSize == FontSizeStep.large.fraction)
        // Everything the publisher styles: untouched, not set to a default.
        #expect(preferences.backgroundColor == nil)
        #expect(preferences.textColor == nil)
        #expect(preferences.fontFamily == nil)
        #expect(preferences.lineHeight == nil)
        #expect(preferences.textAlign == nil)
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
    func coloursComeFromTokens() throws {
        let theme = ReadingTheme(preset: .paper)
        let preferences = theme.preferences(values: theme.preset.values)

        // Same hex string the preset swatch draws, so the card and the page cannot
        // show different colours.
        #expect(preferences.backgroundColor == ReadiumNavigator.Color(hex: theme.background))
        #expect(preferences.textColor == ReadiumNavigator.Color(hex: theme.foreground))
        #expect(try #require(theme.background).hasPrefix("#"))
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
