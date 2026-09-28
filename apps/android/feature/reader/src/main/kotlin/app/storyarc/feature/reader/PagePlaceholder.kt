package app.storyarc.feature.reader

/**
 * The placeholder ratio for a page not yet decoded, and where it comes from.
 *
 * `page-transitions` asks for the placeholder to hold "the correct aspect ratio, so the
 * turn does not jump when the content arrives" — a fixed 2:3 does that for an ordinary
 * comic page and badly for a webtoon, whose pages are many times taller than wide.
 *
 * **Not a page header read.** A page far enough ahead to still show a placeholder has
 * not been fetched yet either, on a slow source, so there are no bytes to read a
 * header from — the gap this was built against is exactly a webtoon scroll from one.
 * The nearest page that *has* decoded is the best guess this app can make without it.
 * iOS's `PagePlaceholder` is the same shape.
 */
internal object PagePlaceholder {
    /** A comic page's own proportions, before anything is known about a webtoon. */
    const val DEFAULT_RATIO = 2f / 3f

    /**
     * The ratio of whichever decoded page is closest to [index], or [DEFAULT_RATIO]
     * when nothing has decoded yet. A plain object, so `PagePlaceholderTest` can drive
     * it with plain numbers — the same reason `EarlyPageTallness` is split out.
     *
     * Broken by the lower index on an exact tie, so the answer does not depend on a
     * `Map`'s own iteration order.
     */
    fun ratio(index: Int, ratios: Map<Int, Float>): Float {
        val nearest = ratios.keys.minWithOrNull(
            compareBy({ kotlin.math.abs(it - index) }, { it }),
        ) ?: return DEFAULT_RATIO
        return ratios[nearest] ?: DEFAULT_RATIO
    }
}
