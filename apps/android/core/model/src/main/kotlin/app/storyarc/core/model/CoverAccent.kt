package app.storyarc.core.model

import android.graphics.Bitmap
import kotlin.math.max
import kotlin.math.min

/**
 * The colour a publication's own artwork brings to its own screens.
 *
 * `native-experience`: "accent and background tinting derive from the publication's
 * cover art", and "the derived colour is adjusted until it meets the contrast floor in
 * the design tokens, rather than being used raw". Both halves live here, because a raw
 * extracted colour that reaches a view is already a bug — the adjustment is not a
 * refinement a caller may skip.
 *
 * Deliberately a mirror of iOS's `CoverAccent`, case for case, for the reason
 * `PageOrdering` is: two extractors that disagree give the same book two different
 * colours on the two platforms, and nothing in either test suite would notice. That is
 * also why this counts pixels itself rather than calling `androidx.palette`, whose
 * quantiser iOS has no equal of and whose answer no JVM unit test can reach.
 */
object CoverAccent {
    /**
     * The floor an accent has to clear against what sits behind it.
     *
     * 3:1, which is what `docs/design.md` §10 requires of "tertiary and accents" and
     * what `pnpm tokens:check` holds the shipped palette to. Text *on* the accent is a
     * different question, answered by [ReadingContrast.bestForeground].
     */
    const val FLOOR = 3.0

    /**
     * How far down a cover is sampled before it is counted.
     *
     * A colour census, not a picture: 32×32 is a thousand pixels, enough that a small
     * logo cannot outvote the sky behind it, and cheap enough to do on the thread that
     * just decoded the page.
     */
    const val SAMPLE_EDGE = 32

    /**
     * The dominant colour of a sampled cover, as `#rrggbb`, or null when it has none.
     *
     * Null is a real answer and the commonest one for manga: a black-and-white cover
     * has no accent to derive, and inventing one from its greys would tint every such
     * book the same muddy sepia. The caller falls back to the brand accent, which is
     * what `native-experience` asks for on a surface with no publication colour of its
     * own.
     *
     * @param pixels packed `0xRRGGBB` — the low 24 bits are read and anything above
     *   them ignored, so an `ARGB` word from either platform arrives correct.
     */
    fun dominant(pixels: IntArray): String? {
        val counts = HashMap<Int, Int>()
        val sums = HashMap<Int, IntArray>()
        for (pixel in pixels) {
            val red = (pixel shr 16) and 0xFF
            val green = (pixel shr 8) and 0xFF
            val blue = pixel and 0xFF
            if (!carriesColour(red, green, blue)) continue
            // Three bits a channel: 512 buckets, which separates a red cape from an
            // orange sky without splitting one sky across four of them.
            val key = ((red shr 5) shl 6) or ((green shr 5) shl 3) or (blue shr 5)
            counts[key] = (counts[key] ?: 0) + 1
            val running = sums.getOrPut(key) { IntArray(3) }
            running[0] += red
            running[1] += green
            running[2] += blue
        }
        // A cover that is nearly all paper, ink and grey has no accent rather than a
        // faint one. A tenth is the line: below it the "dominant" colour is a logo.
        val counted = counts.values.sum()
        if (counted == 0 || counted * 10 < pixels.size) return null
        // Lowest key breaks a tie, so the same cover gives the same colour on every run
        // and on both platforms. A map's own order does not.
        val winner = counts.keys.sortedWith(
            compareByDescending<Int> { counts[it] ?: 0 }.thenBy { it },
        ).first()
        val total = counts[winner] ?: return null
        val sum = sums[winner] ?: return null
        return hex(sum[0] / total, sum[1] / total, sum[2] / total)
    }

    /**
     * Whether a pixel votes at all.
     *
     * Paper, ink and everything close to them are abstentions: they are what a page is
     * made of rather than what it is coloured, and counting them means every cover
     * resolves to off-white.
     */
    private fun carriesColour(red: Int, green: Int, blue: Int): Boolean {
        val highest = max(red, max(green, blue))
        val lowest = min(red, min(green, blue))
        return highest - lowest >= 24 && highest >= 24 && lowest <= 232
    }

    /**
     * [hex], lightened or darkened until it clears [ratio] against [background].
     *
     * Null when no lightness of it can — a mid-grey background has no colour at all
     * that reaches 4.5:1, which is a fact about contrast rather than a search giving up
     * early. Refusing beats returning the nearest miss: the whole point of the
     * adjustment is that what comes out of it is legible.
     *
     * Both directions are tried and the smaller move wins, so an accent stays as close
     * to the artwork as the floor allows. Darkening scales the channels, which holds
     * the hue exactly; lightening blends toward white, which is what a tint is.
     */
    fun legible(hex: String, background: String, ratio: Double = FLOOR): String? {
        val channels = channels(hex) ?: return null
        for (step in 0..STEPS) {
            val amount = step.toDouble() / STEPS
            for (candidate in listOf(darkened(channels, amount), lightened(channels, amount))) {
                if (ReadingContrast.ratio(candidate, background) >= ratio) return candidate
            }
        }
        return null
    }

    /**
     * The whole answer for one cover, or null if it has none to give.
     *
     * The one entry point a screen should use, and the reason it returns a nullable
     * rather than something with a default baked in: `native-experience` puts the brand
     * accent on "a surface with no publication context", and a cover that yields no
     * colour has put the screen in exactly that position. The fallback is the caller's
     * own accent, applied once where it is known.
     */
    fun derived(pixels: IntArray): CoverColours? {
        val dominant = dominant(pixels) ?: return null
        val wash = wash(pixels) ?: return null
        val accent = legible(dominant, wash) ?: return null
        return CoverColours(
            wash = wash,
            accent = accent,
            onAccent = ReadingContrast.bestForeground(accent).first,
        )
    }

    /**
     * A background wash of the cover's colour, dark enough to carry white text.
     *
     * The other half of "accent **and background tinting** derive from the cover".
     * Darkened rather than used raw for the same reason the accent is adjusted: the
     * end-of-publication screen puts white text on this, and a pale cover would put
     * white on cream. Null when the cover has no colour, so the caller keeps black.
     */
    fun wash(pixels: IntArray): String? {
        val channels = channels(dominant(pixels) ?: return null) ?: return null
        for (step in 0..STEPS) {
            val candidate = darkened(channels, step.toDouble() / STEPS)
            if (ReadingContrast.ratio(candidate, "#FFFFFF") >= ReadingContrast.AA) return candidate
        }
        return null
    }

    /**
     * The cover, sampled down to the census grid.
     *
     * Point-sampled on a fixed 32×32 grid rather than scaled proportionally: the
     * aspect ratio of a colour census means nothing, and a fixed grid makes the cost
     * the same for a thumbnail and for a 2000×3000 scan. iOS draws the same grid with
     * interpolation off, so both platforms count the same thousand pixels.
     *
     * A row at a time, because the alternative is a second full-size copy of the page
     * in memory to scale it into, and `native-experience` puts a budget on that.
     *
     * **This used to say "the one part of this file no JVM unit test reaches", and that was
     * only ever true of a plain JVM test.** `:feature:library` runs Robolectric, which
     * supplies a real `Bitmap`, so `DetailAccentTest.aRealCoverComesBackAsTheGrid` puts a
     * solid 64x64 through this and asserts the census grid and the dominant colour -- iOS's
     * `samplesToTheGrid`, which had been the one case the two extractor suites did not
     * share. It still does nothing but hand pixels to [dominant], which is why one case is
     * enough.
     *
     * The `width <= 0` guard is defensive and unreachable from the app: `Bitmap` refuses a
     * zero dimension at construction. A cover that cannot be decoded arrives as `null` and
     * never reaches here at all.
     */
    fun pixels(bitmap: Bitmap): IntArray {
        val width = bitmap.width
        val height = bitmap.height
        if (width <= 0 || height <= 0) return IntArray(0)
        val row = IntArray(width)
        val pixels = IntArray(SAMPLE_EDGE * SAMPLE_EDGE)
        for (down in 0 until SAMPLE_EDGE) {
            val y = min(height - 1, down * height / SAMPLE_EDGE)
            bitmap.getPixels(row, 0, width, 0, y, width, 1)
            for (across in 0 until SAMPLE_EDGE) {
                pixels[down * SAMPLE_EDGE + across] =
                    row[min(width - 1, across * width / SAMPLE_EDGE)]
            }
        }
        return pixels
    }

    /** How finely the lightness walk steps. Twenty is 5 % a move. */
    private const val STEPS = 20

    private fun darkened(channels: IntArray, amount: Double): String {
        val scale = 1 - amount
        return hex(
            (channels[0] * scale).toInt(),
            (channels[1] * scale).toInt(),
            (channels[2] * scale).toInt(),
        )
    }

    private fun lightened(channels: IntArray, amount: Double): String {
        fun blend(channel: Int) = channel + ((255 - channel) * amount).toInt()
        return hex(blend(channels[0]), blend(channels[1]), blend(channels[2]))
    }

    private fun hex(red: Int, green: Int, blue: Int): String {
        val packed = (clamp(red) shl 16) or (clamp(green) shl 8) or clamp(blue)
        return "#" + packed.toString(16).padStart(6, '0').uppercase()
    }

    private fun clamp(channel: Int) = min(255, max(0, channel))

    private fun channels(hex: String): IntArray? {
        val text = hex.removePrefix("#")
        if (text.length != 6) return null
        val value = text.toLongOrNull(16) ?: return null
        return intArrayOf(
            ((value shr 16) and 0xFF).toInt(),
            ((value shr 8) and 0xFF).toInt(),
            (value and 0xFF).toInt(),
        )
    }
}

/**
 * What one cover gives its own screens.
 *
 * Both `#rrggbb`, and both already adjusted: `native-experience` requires the derived
 * colour to be "adjusted until it meets the contrast floor in the design tokens, rather
 * than being used raw", so a value of this type is by construction legible — the wash
 * against the white text on it, the accent against the wash.
 *
 * @property wash the background tint, dark enough to carry white text.
 * @property accent the accent, clear of the floor against [wash].
 * @property onAccent what to write *on* the accent — black or white, whichever it carries.
 */
data class CoverColours(val wash: String, val accent: String, val onAccent: String)
