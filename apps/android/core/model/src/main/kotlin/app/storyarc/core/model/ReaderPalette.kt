package app.storyarc.core.model

import kotlinx.serialization.Serializable
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * WCAG contrast, and the two thresholds `reading-themes` cares about.
 *
 * The same relative-luminance definition the token pipeline uses
 * (`packages/design-tokens/scripts/oklch.mjs`), down to the 0.04045 knee. If the two
 * drifted apart, a pairing could pass the build gate and be refused at runtime, or
 * worse the other way round.
 */
object ReadingContrast {
    /** AAA body text. A derived text colour aims for this. */
    const val AAA = 7.0

    /** AA body text. Below this a pairing is refused outright. */
    const val AA = 4.5

    /** WCAG relative luminance of a `#rrggbb` colour, or null if it is not one. */
    fun luminance(hex: String): Double? {
        val channels = channels(hex) ?: return null
        val linear = channels.map { channel ->
            val value = channel / 255.0
            if (value <= 0.04045) value / 12.92 else ((value + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    /**
     * The contrast ratio between two colours, from 1 to 21.
     *
     * Returns 1 — the worst possible — for a colour it cannot read, rather than null.
     * A malformed hex should never be the reason a pairing is *accepted*.
     */
    fun ratio(one: String, other: String): Double {
        val first = luminance(one) ?: return 1.0
        val second = luminance(other) ?: return 1.0
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /**
     * The most readable text colour for a background, and what it measures.
     *
     * Black or white, and nothing between them can do better: contrast depends only
     * on relative luminance, and black and white are its extremes. So this is not a
     * search that gave up early — it is the whole answer.
     *
     * A mid-tone background has no text colour that reaches AAA at all: grey
     * `#808080` tops out near 5.3. The ratio comes back so a caller can say that
     * rather than silently return something illegible.
     */
    fun bestForeground(background: String): Pair<String, Double> {
        val black = ratio(background, "#000000")
        val white = ratio(background, "#FFFFFF")
        return if (black >= white) "#000000" to black else "#FFFFFF" to white
    }

    private fun channels(hex: String): List<Int>? {
        var text = hex.removePrefix("#")
        // `#abc` is a legal CSS colour and the pickers may hand one over.
        if (text.length == 3) text = text.map { "$it$it" }.joinToString("")
        if (text.length != 6) return null
        val value = text.toLongOrNull(16) ?: return null
        return listOf(
            ((value shr 16) and 0xFF).toInt(),
            ((value shr 8) and 0xFF).toInt(),
            (value and 0xFF).toInt(),
        )
    }
}

/**
 * A reading background and the text colour paired with it.
 *
 * `reading-themes` requires a custom colour to be kept "as a seventh, user-named
 * slot alongside the six presets rather than overwriting one", so the name is part
 * of the value rather than a label attached elsewhere.
 *
 * @property name what the reader called it.
 * @property background `#rrggbb`.
 * @property foreground `#rrggbb`, derived from the background unless overridden.
 */
@Serializable
data class ReaderPalette(
    val name: String,
    val background: String,
    val foreground: String,
) {
    /** What this pairing measures. */
    val contrast: Double get() = ReadingContrast.ratio(background, foreground)

    /**
     * Whether this pairing may be used at all.
     *
     * `reading-themes`: a pairing below 4.5:1 "is refused with the measured ratio
     * stated", because a refusal without a number is just an obstacle.
     */
    val isReadable: Boolean get() = contrast >= ReadingContrast.AA

    /** Whether it reaches the AAA level every built-in preset clears. */
    val meetsAAA: Boolean get() = contrast >= ReadingContrast.AAA

    companion object {
        /** A palette for a background, with the most readable text colour derived. */
        fun derived(name: String, background: String) = ReaderPalette(
            name = name,
            background = background,
            foreground = ReadingContrast.bestForeground(background).first,
        )
    }
}

/**
 * Backgrounds worth offering before the reader reaches for a picker.
 *
 * Not design tokens: a token is a colour the app uses, and these are starting points
 * for a colour the *reader* chooses. They are here rather than in either UI so both
 * platforms offer the same eight, and they are hex for the same reason the preset
 * colours are — Readium parses its own.
 *
 * Every one of them clears AAA against black or white, so picking a swatch never
 * lands the reader in the refusal path. The picker is where that can happen, which
 * is the honest place for it.
 */
val SUGGESTED_BACKGROUNDS = listOf(
    "#FFFFFF", // plain white, for a reader who wants no tint at all
    "#FBF0DA", // cream
    "#F2E8DC", // sepia
    "#E8EFE6", // pale green, the classic eye-strain choice
    "#E6ECF5", // pale blue
    "#2B2B2B", // soft dark, easier than black on an LCD
    "#1B2430", // deep navy
    "#000000", // true black, which is the one an OLED panel rewards
)

/**
 * What each suggested background is called, keyed by its hex.
 *
 * Promoted from a code comment, because a comment is not something a screen reader can
 * say. TalkBack and VoiceOver both read the swatch aloud, and both read
 * "Colour #E8EFE6" one character at a time — which is not a colour a reader can pick
 * from a row of eight.
 *
 * A key rather than a name: core carries no text a reader sees, so each UI turns the key
 * into its own localised string. Here rather than in either UI so both platforms name the
 * same colour the same thing.
 */
val SUGGESTED_BACKGROUND_NAMES = mapOf(
    "#FFFFFF" to "white",
    "#FBF0DA" to "cream",
    "#F2E8DC" to "sepia",
    "#E8EFE6" to "sage",
    "#E6ECF5" to "sky",
    "#2B2B2B" to "charcoal",
    "#1B2430" to "navy",
    "#000000" to "trueBlack",
)

/**
 * Text colours worth offering when a reader overrides the derived one.
 *
 * Deliberately not only black and white. A warm dark on cream is a real preference,
 * and some of these will fail against some backgrounds — which is the point:
 * `reading-themes` requires the refusal to state its ratio, and a list that can never
 * fail would leave that path untested by any real use.
 */
val SUGGESTED_FOREGROUNDS = listOf(
    "#000000",
    "#2A2622", // warm dark
    "#1B2430", // cool dark
    "#FFFFFF",
    "#EDE6DA", // warm light
    "#D8E0EA", // cool light
)
