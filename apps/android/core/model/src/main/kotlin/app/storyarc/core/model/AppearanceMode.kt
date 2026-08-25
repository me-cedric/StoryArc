package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * What the reader chose in Settings › Appearance.
 *
 * `settings-and-about` requires System, Light, Dark and OLED Dark, defaulting to
 * System, applied without a restart. Reading themes are deliberately independent of
 * this — a dark chrome with a paper-white page is a legitimate preference, and the spec
 * says so.
 *
 * Natural is deliberately *not* a case. The spec calls it "a theme rather than an
 * appearance… carries its own light and dark variants", so it sits alongside this
 * polarity rather than inside it. Putting it here would force a choice between Natural
 * and dark mode that the spec exists to avoid.
 *
 * In the domain rather than the design system, because it is a *setting*: it is stored,
 * it is one of the values [AppSettings] carries, and the mapping to a colour scheme and
 * a palette is the design system's business rather than its definition. The same split
 * `ReaderTypeface` already uses.
 */
@Serializable
enum class AppearanceMode {
    SYSTEM,
    LIGHT,
    DARK,

    /**
     * True black chrome, for OLED panels where black draws no power.
     *
     * The reader surface stays *above* true black even here. Pure black smears on OLED
     * during a page turn, which is the exact motion this app is built around — so the
     * setting is honoured where it helps and the palette declines it where it does not.
     * The generated `oledDark` tokens carry that decision, not this type.
     */
    OLED_DARK,
    ;

    /** Whether this appearance wants the true-black palette rather than the warm one. */
    val isTrueBlack: Boolean get() = this == OLED_DARK
}
