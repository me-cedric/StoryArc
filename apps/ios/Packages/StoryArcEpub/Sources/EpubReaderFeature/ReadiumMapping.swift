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
    func preferences(values: ThemeValues, transition: PageTransition = .slide) -> EPUBPreferences {
        var preferences = EPUBPreferences()

        // The one axis that always applies, under every preset including Original.
        preferences.fontSize = values.fontSize.fraction

        // Scroll mode for reflowable text is *Readium's*, not ours. It has a
        // preference for exactly this, and a container of our own over a web view that
        // already paginates would be two things fighting for the same gesture.
        //
        // Which is also why `page-transitions`' four modes divide the way they do for
        // an EPUB: Slide is Readium paginated, Scroll is this flag, and the two that
        // animate a picture of a page need the raster that does not exist yet.
        preferences.scroll = transition.isScroll

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
        // Nil rather than false when the reader has not asked for it, so the publication
        // keeps whatever its own stylesheet says. Passing false would be StoryArc turning
        // off a publisher's hyphenation on every book that wanted it.
        preferences.hyphens = values.isHyphenated ? true : nil
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
        // The reader's own choice wins over the preset's, which is what makes the
        // custom slot reach the page at all.
        if let custom { return custom.background }
        return switch preset {
        case .original: StoryArcReadingThemeHex.originalBg
        case .quiet: StoryArcReadingThemeHex.quietBg
        case .paper: StoryArcReadingThemeHex.paperBg
        case .bold: StoryArcReadingThemeHex.boldBg
        case .calm: StoryArcReadingThemeHex.calmBg
        case .focus: StoryArcReadingThemeHex.focusBg
        }
    }

    var foreground: String {
        if let custom { return custom.foreground }
        return switch preset {
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
    ///
    /// Every other case is the CSS family name the domain already carries, so a new
    /// bundled face needs no change here — only a declaration in `FontDeclarations`
    /// and the file itself.
    var readium: FontFamily? {
        cssFamily.map { FontFamily(rawValue: $0) }
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
