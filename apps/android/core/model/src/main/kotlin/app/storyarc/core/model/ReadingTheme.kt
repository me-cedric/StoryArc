package app.storyarc.core.model

import kotlinx.serialization.Serializable
/**
 * The named reading themes.
 *
 * `reading-themes` lists six, and they are not the four the main `ebook-reader`
 * spec used to name — this change replaces Paper/Sepia/Night/High Contrast with a
 * set that includes *Original*, which is the one that could not be expressed
 * before. Original is not a colour scheme; it is the absence of one.
 *
 * The colours themselves live in `packages/design-tokens/tokens/color.json` under
 * `readingThemes`, so all six go through the existing AAA contrast gate and a
 * preset that fails 7:1 fails the build.
 */
@Serializable
enum class ThemePreset {
    /** The publication as its publisher styled it. */
    ORIGINAL,

    /** Low-contrast dark: soft off-white on deep neutral, tightened spacing. */
    QUIET,

    /** Neutral light: book-stock white, serif, comfortable spacing. */
    PAPER,

    /**
     * High contrast, heavier weight, wider spacing. Low vision without leaving the
     * aesthetic.
     */
    BOLD,

    /** Warm dim: cream on brown, generous line height. Long evening sessions. */
    CALM,

    /** Narrow measure, high contrast, minimal decoration. Fewest words per line. */
    FOCUS,

    ;

    /**
     * Whether the publication's own stylesheet stays in force.
     *
     * True for [ORIGINAL] alone, and it is what makes five of the nine axes inert
     * under it. `reading-themes` requires those controls to say so rather than sit
     * there doing nothing.
     */
    val keepsPublisherStyles: Boolean get() = this == ORIGINAL
}

/**
 * The axes a reading theme is made of.
 *
 * Exactly the list in `reading-themes`, and each one carries the fact that decides
 * whether its control is usable: whether Readium can apply it while the publisher's
 * stylesheet is still in force. That is a property of the axis, not of the UI, which
 * is why it lives here.
 */
@Serializable
enum class ThemeAxis {
    FONT_SIZE,
    FONT_FAMILY,
    BOLD_TEXT,
    LINE_SPACING,
    CHARACTER_SPACING,
    WORD_SPACING,
    PARAGRAPH_SPACING,
    MARGINS,
    TEXT_ALIGNMENT,
    HYPHENATION,

    ;

    /**
     * Whether this axis needs the publisher's stylesheet switched off.
     *
     * From `design.md`'s mapping table, which is Readium's behaviour rather than
     * ours: font size, family, weight and margins reach the page regardless;
     * spacing and alignment are overridden by publisher CSS.
     */
    val requiresPublisherStylesOff: Boolean
        get() = when (this) {
            FONT_SIZE, FONT_FAMILY, BOLD_TEXT, MARGINS -> false
            // A publisher's stylesheet can set `hyphens` too, and Readium's own mapping
            // puts it with the properties publisher CSS overrides.
            LINE_SPACING, CHARACTER_SPACING, WORD_SPACING, PARAGRAPH_SPACING, TEXT_ALIGNMENT,
            HYPHENATION,
            -> true
        }
}

/**
 * A preset, plus wherever the reader has since departed from it.
 *
 * Deliberately holds no typographic *values*. A preset is a named `EpubPreferences`
 * value and Readium owns those (`design.md`: "no preset machinery to build"). What
 * the app has to know, and Readium will not tell it, is which preset was chosen and
 * which axes the reader has moved since — because `reading-themes` requires a
 * deviated preset to stay selected and be "marked as modified", with one action to
 * put it back.
 *
 * iOS's `ReadingTheme` is the same value with the same rules.
 */
@Serializable
data class ReadingTheme(
    val preset: ThemePreset = ThemePreset.PAPER,
    /** The axes moved since the preset was adopted. */
    val deviations: Set<ThemeAxis> = emptySet(),
    /**
     * The reader's own colours, when they have chosen some.
     *
     * `reading-themes` requires a custom colour to be "a seventh, user-named slot
     * alongside the six presets rather than overwriting one" — so it sits beside
     * `preset` instead of being one of its cases. The preset still supplies the
     * typography: choosing a background is a decision about colour, and it should
     * not silently reset the line height the reader spent a minute on.
     */
    val custom: ReaderPalette? = null,
) {
    /** Whether to mark the preset as modified rather than plainly active. */
    val isModified: Boolean get() = deviations.isNotEmpty()

    /** Whether the reader's own colours are in force. */
    val isCustom: Boolean get() = custom != null

    /**
     * Whether an axis can reach the page at all.
     *
     * `reading-themes`: under Original the dependent axes are "shown as unavailable
     * with a one-line explanation, not hidden and not shown as dead controls".
     * Hidden loses the explanation; a live-looking control that does nothing is
     * worse than either.
     */
    fun isEffective(axis: ThemeAxis): Boolean =
        !(preset.keepsPublisherStyles && axis.requiresPublisherStylesOff)

    /** The axes a reader can actually move under this preset. */
    val effectiveAxes: List<ThemeAxis> get() = ThemeAxis.entries.filter(::isEffective)

    /**
     * Adopts a preset, which discards any deviation from the last one.
     *
     * `reading-themes`: tapping a preset applies "every axis the preset defines ...
     * at once". Carrying a previous deviation across would mean the preset the
     * reader just tapped is not the one they get.
     */
    fun adopting(preset: ThemePreset) = ReadingTheme(preset)

    /**
     * Puts the reader's own colours in force, keeping the typography they have.
     *
     * Kept separate from `adopting` for the reason the spec gives: the custom slot
     * sits alongside the six rather than replacing one of them, so choosing it is
     * not the same act as choosing a preset. It also cannot be chosen under
     * Original, where the publisher's own colours are the point.
     */
    fun adopting(palette: ReaderPalette): ReadingTheme =
        if (preset.keepsPublisherStyles) this else copy(custom = palette)

    /** Drops the reader's own colours and goes back to the preset's. */
    fun discardingCustomColours() = copy(custom = null)

    /**
     * Records that an axis was moved.
     *
     * An axis that cannot reach the page is not recorded as a deviation: nothing
     * changed, so calling the preset modified would be a lie the reader could see.
     */
    fun deviating(on: ThemeAxis): ReadingTheme =
        if (isEffective(on)) copy(deviations = deviations + on) else this

    /**
     * Puts every axis back to the preset's own values.
     *
     * `reading-themes`, *The reset names what it restores*: "every axis returns to that
     * preset's published value, including any the reader never touched **AND** the other five
     * presets, **the custom colour slot**, the per-series memory and the global default are
     * unchanged, because a reset is not a factory reset."
     *
     * **The custom palette therefore survives, and that is the whole difference from
     * [adopting].** This used to be spelled `ReadingTheme(preset)`, which is `adopting`'s
     * body — and adopting a preset drops the palette on purpose, because tapping one of the
     * six presets is how a reader leaves their own colours. A reset is not that act. A reader
     * who had made a palette, chosen Calm and nudged the line spacing lost the palette by
     * putting the line spacing back. `ThemeResetTest` is why it does not now.
     */
    fun restored() = ReadingTheme(preset, custom = custom)
}
