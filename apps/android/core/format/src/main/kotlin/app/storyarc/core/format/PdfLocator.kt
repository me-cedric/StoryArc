package app.storyarc.core.format

/**
 * Where in a PDF a mark or a hit is.
 *
 * `ebook-reader` stores a highlight against "the renderer's own locator", and for a
 * reflowable publication that is Readium's JSON. A PDF has no such renderer: its text is a run
 * of characters per page, and the only thing that finds the same words again is the page plus
 * the offsets into it. So this is that locator, and it is carried in the same
 * `Annotation.locator` field the EPUB reader uses -- which is what lets one `AnnotationExport`
 * write both without knowing the difference.
 *
 * Written and read by hand rather than through a serializer. Three integers do not need one,
 * and hand-writing them is what guarantees the two platforms produce the *same* string rather
 * than two encoders' idea of the same record -- key order included.
 *
 * Offsets are UTF-16 code units into the page's text, which is what both platforms' text APIs
 * count in: `String` indices on this side, `NSRange` on the other.
 *
 * iOS's `PdfLocator` reads and writes the same string.
 */
data class PdfLocator(
    /** Zero-based, the way every page index in the reader is. */
    val page: Int,
    /** First code unit of the run, inclusive. */
    val start: Int,
    /** One past the last code unit of the run. */
    val end: Int,
) {
    /** The locator as it is stored. Compact, ordered, and the same on both platforms. */
    val json: String get() = """{"page":$page,"start":$start,"end":$end}"""

    companion object {
        /**
         * Reads one back, or null when the string is not one.
         *
         * Null rather than a throw, and lenient about what surrounds the numbers: a locator
         * that cannot be read means a mark that cannot be drawn, which the reader already
         * handles by leaving it out of the page rather than by failing to open the book.
         */
        fun of(json: String): PdfLocator? {
            val page = number("page", json) ?: return null
            val start = number("start", json) ?: return null
            val end = number("end", json) ?: return null
            if (page < 0 || start < 0 || end < start) return null
            return PdfLocator(page, start, end)
        }

        private fun number(key: String, json: String): Int? {
            val keyAt = json.indexOf("\"" + key + "\"")
            if (keyAt < 0) return null
            val colon = json.indexOf(':', keyAt)
            if (colon < 0) return null
            val digits = json.drop(colon + 1)
                .takeWhile { it == ' ' || it == '-' || it.isDigit() }
                .trim()
            return digits.toIntOrNull()
        }
    }
}
