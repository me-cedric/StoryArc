package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import app.storyarc.core.designsystem.theme.rememberHighContrast
import app.storyarc.core.model.CoverAccent
import app.storyarc.core.model.CoverColours

/**
 * The colours a page takes from its own book.
 *
 * `publication-detail`: "the background carries a colour derived from that cover, so the
 * screen belongs to the book", and the derived colour "is adjusted in lightness until it
 * clears the floor, however far that is from the cover's own colour". Both halves are
 * already written and already tested in `core.model.CoverAccent`, which is a deliberate
 * mirror of iOS's extractor case for case — so this file adds no colour science at all.
 * What was missing was a caller: until now the library half of the app had never asked the
 * extractor a single question, and the only caller anywhere was the reader's thumbnails.
 *
 * Nothing here reaches `androidx.palette`. Adding it would give the same book two
 * different colours on the two platforms, which is exactly what the mirrored extractor
 * exists to prevent.
 */
internal data class DetailAccent(
    /** The page's ground, dark enough to carry white text. */
    val wash: Color,
    /** The accent, clear of the 3:1 floor against [wash]. */
    val accent: Color,
    /** What to write *on* the accent — black or white, whichever it carries. */
    val onAccent: Color,
)

/**
 * A `#rrggbb` from the extractor as a Compose colour.
 *
 * Internal and separately named so the parsing has a unit test of its own: the extractor's
 * output format is a contract between two modules, and a screen that silently drew black
 * for every cover would look like a colour bug rather than a parsing one.
 */
internal fun parseHex(hex: String): Color? {
    val text = hex.removePrefix("#")
    if (text.length != 6) return null
    val value = text.toLongOrNull(16) ?: return null
    return Color(0xFF000000L.or(value))
}

/** The whole answer for one cover, or null when it has none to give. */
internal fun detailAccentOf(colours: CoverColours): DetailAccent? {
    val wash = parseHex(colours.wash) ?: return null
    val accent = parseHex(colours.accent) ?: return null
    val onAccent = parseHex(colours.onAccent) ?: return null
    return DetailAccent(wash = wash, accent = accent, onAccent = onAccent)
}

/**
 * The colours for this cover, or null for a page that must stay on plain surfaces.
 *
 * Null is a real answer and the page has to be legible on it, three ways over:
 *
 * - **The cover has not arrived.** The page is composed before its cover is decoded, so it
 *   renders with no accent and adopts one when the bitmap lands.
 * - **The cover yields nothing.** A monochrome, nearly-white or nearly-black cover has no
 *   colour to derive, and `CoverAccent` returns null rather than inventing a muddy sepia —
 *   the manga case, and the commonest one. The delta requires the page to fall back to the
 *   app's own accent instead of drawing "a wash so faint or so dark that the screen looks
 *   broken".
 * - **The system asked for more contrast.** The delta: the wash "is replaced by a plain
 *   surface rather than being softened". Softening is how a screen ends up marginally below
 *   the floor instead of clearly above it.
 *
 * Android has no reduced-transparency setting to answer the delta's other half — the
 * platform ships contrast stops and no transparency switch — so contrast is the whole
 * question here. That is the same kind of divergence the direction's register already
 * records for the Reduce-Motion copy: the behaviour is the platform's own, and inventing a
 * second setting would be worse than reading the one that exists.
 *
 * Sampling runs off [Bitmap.hashCode]-stable identity rather than on every recomposition:
 * a thousand-pixel census is cheap, and doing it on each frame of a scroll is not.
 */
@Composable
internal fun rememberDetailAccent(cover: Bitmap?): DetailAccent? {
    val isHighContrast = rememberHighContrast()
    return remember(cover, isHighContrast) {
        if (cover == null || isHighContrast) {
            null
        } else {
            CoverAccent.derived(CoverAccent.pixels(cover))?.let(::detailAccentOf)
        }
    }
}
