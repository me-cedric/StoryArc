package app.storyarc.core.format

/**
 * A cover for an EPUB that declares none.
 *
 * `publication-formats`: "WHEN an EPUB declares a cover image THEN that image is used;
 * otherwise the first page of the spine is rendered as the cover." Most publications
 * that declare no cover still *open* on one — a `cover.xhtml` holding a single image,
 * which is what a fixed-layout EPUB's first page is by construction and what a converter
 * emits for a reflowable one. So the first spine item is read and the image it shows
 * becomes the cover, at which point it is an ordinary path inside the container and
 * every layer above — the indexer, [CoverLoader], [CoverCache] — treats it exactly like
 * a declared one.
 *
 * **What this does not do.** A first spine item that shows no image at all leaves the
 * publication without a cover, and the library draws its placeholder. Rasterising
 * arbitrary XHTML means a `WebView` on both platforms, which is a decision ADR-0005
 * scoped to reading a book rather than to drawing a thumbnail of one — so the cheap
 * nine-tenths is taken and the expensive tenth is left named rather than half-built.
 *
 * iOS's `EpubSpineCover` is the same two rules in the same order.
 */
object EpubSpineCover {

    /**
     * Every way an XHTML page can point at an image, in the order they are looked for.
     *
     * `src` covers `<img>`, `href` and `xlink:href` cover SVG `<image>` — which is what
     * a fixed-layout page produced by InDesign or Calibre uses at least as often as
     * `<img>` — and `url(...)` covers a page whose only picture is a CSS background.
     * Nothing here parses XHTML: a cover page is one element deep and a DOM would be
     * more code for the same answer, exactly as [EpubReader] argues for the package
     * document.
     */
    fun imageReferences(xhtml: ByteArray): List<String> {
        val text = String(xhtml, Charsets.UTF_8)
        val found = mutableListOf<String>()
        for (attribute in listOf("src=", "xlink:href=", "href=", "url(")) {
            var from = 0
            while (true) {
                val start = text.indexOf(attribute, from)
                if (start < 0) break
                from = start + attribute.length
                val value = quoted(text, from) ?: continue
                if (value.isNotEmpty() && value !in found) found += value
            }
        }
        return found
    }

    /** The value that opens at [offset]: `"…"`, `'…'`, or up to `)`. */
    private fun quoted(text: String, offset: Int): String? {
        val opening = text.getOrNull(offset) ?: return null
        if (opening == '"' || opening == '\'') {
            val closing = text.indexOf(opening, offset + 1)
            if (closing < 0) return null
            return text.substring(offset + 1, closing)
        }
        // `url(` with no quotes, which CSS allows.
        val closing = text.indexOf(')', offset)
        if (closing < 0) return null
        return text.substring(offset, closing).trim()
    }

    /**
     * Whether a reference names something StoryArc could decode as a cover.
     *
     * The extension, not the bytes: this runs against a name inside a container that has
     * not been read yet, and reading every referenced entry to find out would cost
     * exactly what lazy cover extraction exists to avoid.
     */
    fun looksLikeAnImage(reference: String): Boolean = PageOrdering.isPage(reference)

    /** The directory an href inside [path] resolves against. */
    fun directoryOf(path: String): String = path.substringBeforeLast('/', "")

    /** An href relative to the document that declared it, with any fragment dropped. */
    fun resolve(href: String, base: String): String {
        val withoutFragment = href.substringBefore('#')
        if (withoutFragment.startsWith("/")) return withoutFragment.removePrefix("/")
        if (base.isEmpty()) return withoutFragment

        val segments = base.split('/').filter { it.isNotEmpty() }.toMutableList()
        for (part in withoutFragment.split('/')) {
            when (part) {
                "", "." -> continue
                ".." -> if (segments.isNotEmpty()) segments.removeAt(segments.lastIndex)
                else -> segments += part
            }
        }
        return segments.joinToString("/")
    }
}

/**
 * The publication's cover path: the one it declares, or the image its first page shows.
 *
 * Null when neither exists, which the caller shows as a placeholder rather than as an
 * error — a book with no cover is a book, not a failure.
 */
suspend fun EpubReader.coverOrSpineHref(): String? {
    coverHref?.let { return it }
    val first = spine.firstOrNull() ?: return null
    // The item's own bytes may be missing from a damaged container. That is not worth an
    // error either: it means there is no cover to be had.
    val xhtml = runCatching { data(first.href) }.getOrNull() ?: return null
    val base = EpubSpineCover.directoryOf(first.href)
    for (reference in EpubSpineCover.imageReferences(xhtml)) {
        if (!EpubSpineCover.looksLikeAnImage(reference)) continue
        val resolved = EpubSpineCover.resolve(reference, base)
        // Only a path the container actually holds. A remote `src`, or one that walked
        // out of the container, is not a cover.
        if (pathToEntry.containsKey(resolved)) return resolved
    }
    return null
}
