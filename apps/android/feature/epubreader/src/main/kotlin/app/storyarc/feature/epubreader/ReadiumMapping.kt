package app.storyarc.feature.epubreader

import android.graphics.Color as AndroidColor
import app.storyarc.core.designsystem.tokens.StoryArcReadingThemeHex
import app.storyarc.core.model.ReaderTextAlignment
import app.storyarc.core.model.ReaderTypeface
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.isScroll
import app.storyarc.core.model.ReadingTheme
import app.storyarc.core.model.ThemePreset
import app.storyarc.core.model.ThemeValues
import app.storyarc.core.model.values
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.Color
import org.readium.r2.navigator.preferences.FontFamily
import org.readium.r2.navigator.preferences.TextAlign
import org.readium.r2.shared.ExperimentalReadiumApi

/**
 * Turns a reading theme into the preferences Readium understands.
 *
 * `design.md`: "a preset is therefore just a named `EpubPreferences` value. No
 * preset machinery to build." This is where that sentence is cashed in — the domain
 * carries the numbers and the names, and this file is the only place that knows what
 * Readium calls them.
 *
 * Keeping it to one file is the point. If Readium renames an axis or a preference
 * turns out to be inert, the compiler points here and nowhere else. iOS's
 * `ReadiumMapping.swift` is the same mapping.
 *
 * @param values the typography in force. The preset's own values unless the reader
 *   has moved an axis, which is why this is a parameter rather than read off the
 *   preset.
 */
// Readium marks its preferences API experimental. Opted into here rather than
// module-wide, so the day an axis changes the compiler points at this one function.
@OptIn(ExperimentalReadiumApi::class)
internal fun ReadingTheme.preferences(
    values: ThemeValues,
    transition: PageTransition = PageTransition.SLIDE,
): EpubPreferences {
    // The one axis that always applies, under every preset including Original.
    val fontSize = values.fontSize.fraction

    // Scroll mode for reflowable text is *Readium's*, not ours. It has a preference for
    // exactly this, and a container of our own over a web view that already paginates
    // would be two things fighting for the same gesture.
    //
    // Which is also why `page-transitions`' four modes divide the way they do for an
    // EPUB: Slide is Readium paginated, Scroll is this flag, and the two that animate a
    // picture of a page are drawn by StoryArc over the pager. Fast fade dips through the
    // page colour in `FadeTurn`; Curl needs the incoming page as a texture, which is
    // task 4.3b.
    val scroll = transition.isScroll

    // Original means the publication as published, so it takes no override.
    if (preset.keepsPublisherStyles) {
        return EpubPreferences(fontSize = fontSize, publisherStyles = true, scroll = scroll)
    }

    return EpubPreferences(
        scroll = scroll,
        backgroundColor = Color(AndroidColor.parseColor(background)),
        textColor = Color(AndroidColor.parseColor(foreground)),
        fontFamily = values.typeface.readium,
        fontSize = fontSize,
        // A weight rather than a family: `reading-themes` says bold "raises weight
        // without changing family".
        fontWeight = if (values.isBold) 1.5 else null,
        // Null rather than false when the reader has not asked for it, so the publication
        // keeps whatever its own stylesheet says. Passing false would be StoryArc turning
        // off a publisher's hyphenation on every book that wanted it.
        hyphens = if (values.isHyphenated) true else null,
        letterSpacing = values.letterSpacing,
        lineHeight = values.lineHeight,
        pageMargins = values.pageMargins,
        paragraphSpacing = values.paragraphSpacing,
        publisherStyles = false,
        textAlign = values.textAlignment.readium,
        wordSpacing = values.wordSpacing,
    )
}

/**
 * The theme's background, from the design tokens.
 *
 * Hex rather than a Compose colour, because Readium parses its own and the token
 * pipeline emits both from one source — so the reader's page and the preset's swatch
 * cannot drift apart.
 */
internal val ReadingTheme.background: String
    // The reader's own choice wins over the preset's, which is what makes the custom
    // slot reach the page at all.
    get() = custom?.background ?: when (preset) {
        ThemePreset.ORIGINAL -> StoryArcReadingThemeHex.originalBg
        ThemePreset.QUIET -> StoryArcReadingThemeHex.quietBg
        ThemePreset.PAPER -> StoryArcReadingThemeHex.paperBg
        ThemePreset.BOLD -> StoryArcReadingThemeHex.boldBg
        ThemePreset.CALM -> StoryArcReadingThemeHex.calmBg
        ThemePreset.FOCUS -> StoryArcReadingThemeHex.focusBg
    }

internal val ReadingTheme.foreground: String
    get() = custom?.foreground ?: when (preset) {
        ThemePreset.ORIGINAL -> StoryArcReadingThemeHex.originalFg
        ThemePreset.QUIET -> StoryArcReadingThemeHex.quietFg
        ThemePreset.PAPER -> StoryArcReadingThemeHex.paperFg
        ThemePreset.BOLD -> StoryArcReadingThemeHex.boldFg
        ThemePreset.CALM -> StoryArcReadingThemeHex.calmFg
        ThemePreset.FOCUS -> StoryArcReadingThemeHex.focusFg
    }

/**
 * `null` leaves the publication's own family in place, which is what PUBLISHER means.
 *
 * Every other case is the CSS family name the domain already carries, so a new
 * bundled face needs no change here — only a declaration in `FontDeclarations` and
 * the file itself.
 */
private val ReaderTypeface.readium: FontFamily?
    get() = cssFamily?.let(::FontFamily)

private val ReaderTextAlignment.readium: TextAlign?
    get() = when (this) {
        ReaderTextAlignment.PUBLISHER -> null
        ReaderTextAlignment.LEFT -> TextAlign.LEFT
        ReaderTextAlignment.JUSTIFIED -> TextAlign.JUSTIFY
    }
