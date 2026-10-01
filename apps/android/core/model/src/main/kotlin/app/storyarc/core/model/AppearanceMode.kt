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

/**
 * The reading theme that goes with an app appearance.
 *
 * `settings-and-about` keeps the two apart by default — "a dark app chrome with a
 * paper-white page is a legitimate preference" — and then allows "a single opt-in setting"
 * that links them. This is the mapping that setting uses.
 *
 * Two presets, not four. Light is Paper and every dark appearance is Quiet, because the
 * difference between Dark and OLED Dark is the *chrome*'s black point and a reading surface
 * is deliberately never pure black anyway. Mapping OLED Dark to a darker reading theme
 * would undo the reason that appearance exists.
 *
 * System resolves to whichever the device is showing, so it is the caller's job to pass the
 * resolved appearance rather than SYSTEM — there is no answer for "follow the device" here,
 * only for what the device currently says. A caller that has not resolved it gets the light
 * answer rather than a crash.
 */
fun presetMatching(appearance: AppearanceMode): ThemePreset =
    presetMatching(appearance, light = ThemePreset.PAPER, dark = ThemePreset.QUIET)

/**
 * The reading theme that goes with an app appearance, from the reader's own pair.
 *
 * `ebook-reader` / *Theme follows appearance*: the switch lands on "the light and dark
 * reading themes the reader chose as their pair, not to an arbitrary default" — so the pair
 * is an input here rather than the fixed Paper/Quiet [presetMatching] falls back to for a
 * caller that has none to offer.
 *
 * Two presets, not four, for the same reason the single-argument overload documents: Dark
 * and OLED Dark both resolve to [dark], because a reading surface is deliberately never
 * pure black regardless of which dark chrome sits around it.
 */
fun presetMatching(
    appearance: AppearanceMode,
    light: ThemePreset,
    dark: ThemePreset,
): ThemePreset = when (appearance) {
    AppearanceMode.LIGHT, AppearanceMode.SYSTEM -> light
    AppearanceMode.DARK, AppearanceMode.OLED_DARK -> dark
}
