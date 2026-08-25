internal import ReadiumNavigator

internal import DesignSystem
internal import StoryArcCore

/// Turns a reading theme into the preferences Readium understands.
///
/// `design.md`: "a preset is therefore just a named `EPUBPreferences` value. No
/// preset machinery to build." This is where that sentence is cashed in — the
/// domain carries the numbers and the names, and this file is the only place that
/// knows what Readium calls them.
///
/// Keeping it to one file is the point. If Readium renames an axis or a preference
/// turns out to be inert, the compiler points here and nowhere else.
extension ReadingTheme {
    /// The preferences for this theme, with the reader's own overrides applied.
    ///
    /// - Parameter values: the typography in force. The preset's own values unless
    ///   the reader has moved an axis, which is why this is a parameter rather than
    ///   read off the preset.
    func preferences(values: ThemeValues) -> EPUBPreferences {
        var preferences = EPUBPreferences()

        // The one axis that always applies, under every preset including Original.
        preferences.fontSize = values.fontSize.fraction

        // Original means the publication as published. Everything below this line
        // is an override, so Original takes none of it.
        guard !preset.keepsPublisherStyles else {
            preferences.publisherStyles = true
            return preferences
        }

        preferences.publisherStyles = false
        preferences.backgroundColor = Self.colour(background)
        preferences.textColor = Self.colour(foreground)
        preferences.fontFamily = values.typeface.readium
        // A weight rather than a family: `reading-themes` says bold "raises weight
        // without changing family".
        preferences.fontWeight = values.isBold ? 1.5 : nil
        preferences.lineHeight = values.lineHeight
        preferences.letterSpacing = values.letterSpacing
        preferences.wordSpacing = values.wordSpacing
        preferences.paragraphSpacing = values.paragraphSpacing
        preferences.pageMargins = values.pageMargins
        preferences.textAlign = values.textAlignment.readium

        return preferences
    }

    /// The theme's background, from the design tokens.
    ///
    /// Hex rather than a `SwiftUI.Color`, because Readium parses its own and the
    /// token pipeline emits both from one source — so the reader's page and the
    /// preset's swatch cannot drift apart.
    var background: String {
        switch preset {
        case .original: StoryArcReadingThemeHex.originalBg
        case .quiet: StoryArcReadingThemeHex.quietBg
        case .paper: StoryArcReadingThemeHex.paperBg
        case .bold: StoryArcReadingThemeHex.boldBg
        case .calm: StoryArcReadingThemeHex.calmBg
        case .focus: StoryArcReadingThemeHex.focusBg
        }
    }

    var foreground: String {
        switch preset {
        case .original: StoryArcReadingThemeHex.originalFg
        case .quiet: StoryArcReadingThemeHex.quietFg
        case .paper: StoryArcReadingThemeHex.paperFg
        case .bold: StoryArcReadingThemeHex.boldFg
        case .calm: StoryArcReadingThemeHex.calmFg
        case .focus: StoryArcReadingThemeHex.focusFg
        }
    }

    private static func colour(_ hex: String) -> ReadiumNavigator.Color? {
        ReadiumNavigator.Color(hex: hex)
    }
}

private extension ReaderTypeface {
    /// `nil` leaves the publication's own family in place, which is what
    /// `publisher` means.
    var readium: FontFamily? {
        switch self {
        case .publisher: nil
        case .serif: .serif
        case .sans: .sansSerif
        }
    }
}

private extension ReaderTextAlignment {
    var readium: ReadiumNavigator.TextAlignment? {
        switch self {
        case .publisher: nil
        case .left: .left
        case .justified: .justify
        }
    }
}
