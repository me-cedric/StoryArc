package app.storyarc.core.format

import app.storyarc.core.model.SearchSnippet

/** One hit inside a PDF's text layer. */
data class PdfTextMatch(
    val locator: PdfLocator,
    val snippet: SearchSnippet,
)

/**
 * Finding a word in a page of PDF text.
 *
 * `ebook-reader`: a PDF that "contains a text layer" gets in-publication search, and
 * `Navigation and annotation` says matches are "listed with surrounding context". Both
 * platforms have a native PDF search -- `Page.searchText` on this side,
 * `PDFDocument.findString` on the other -- and neither of them reports the words around a hit,
 * which is the half a list row needs. So the page's text is read once and searched here
 * instead, and the context comes out of the same string the offsets point into.
 *
 * That is also what keeps the two readers honest about [SearchSnippet]: there is one snippet
 * rule in this app, the one the EPUB reader already uses, and a PDF hit is trimmed by it
 * rather than by a second rule that would drift from it.
 *
 * iOS's `PdfTextSearch` cuts the same matches.
 */
object PdfTextSearch {

    /**
     * How many characters either side of a hit are handed to [SearchSnippet].
     *
     * The snippet's own budget: it spends what it is given and no more, so handing it exactly
     * that much makes the trimming deterministic everywhere except at the edges of a page,
     * which is where the spare-budget rule is supposed to show.
     */
    const val CONTEXT: Int = SearchSnippet.BUDGET

    /**
     * How many hits one search reports.
     *
     * A search for "the" in a four-hundred-page manual has tens of thousands of answers and no
     * reader scrolls them. The cap is stated in the list rather than applied quietly --
     * `ebook-reader` forbids a control that promises what it does not deliver, and a truncated
     * list that says it is truncated keeps that promise.
     */
    const val MATCH_LIMIT: Int = 200

    /**
     * Every occurrence of [query] in one page's text, in reading order.
     *
     * Case-insensitive, because a reader searching for a name does not capitalise it. Not
     * diacritic-insensitive: the two platforms fold accents differently, and a search that
     * found different things on each would be a divergence nothing could assert.
     */
    fun matches(
        text: String,
        page: Int,
        query: String,
        limit: Int = MATCH_LIMIT,
    ): List<PdfTextMatch> {
        if (query.isEmpty() || limit <= 0 || text.isEmpty()) return emptyList()

        val found = mutableListOf<PdfTextMatch>()
        var cursor = 0

        while (found.size < limit && cursor <= text.length - query.length) {
            val start = text.indexOf(query, cursor, ignoreCase = true)
            if (start < 0) break
            val end = start + query.length

            found += PdfTextMatch(
                locator = PdfLocator(page = page, start = start, end = end),
                snippet = SearchSnippet.of(
                    before = condensed(text.substring(maxOf(0, start - CONTEXT), start)),
                    match = condensed(text.substring(start, end)),
                    after = condensed(text.substring(end, minOf(text.length, end + CONTEXT))),
                ),
            )

            // Past the hit, so an overlapping second match of the same run is not reported
            // twice. An empty query cannot reach here, so this always advances.
            cursor = end
        }
        return found
    }

    /**
     * The words a locator names, or null when it does not name any of this text.
     *
     * What the reader shows in a mark's row, and what goes into the export.
     */
    fun text(locator: PdfLocator, text: String): String? {
        if (locator.start >= text.length || locator.end > text.length) return null
        if (locator.start >= locator.end) return null
        return condensed(text.substring(locator.start, locator.end)).ifEmpty { null }
    }

    /**
     * One line out of text that was laid out in columns.
     *
     * A PDF's text layer carries the line breaks of the *page*, not of the sentence, so a
     * snippet taken straight out of it arrives with newlines through the middle of it and
     * reads as three rows in one. The offsets are untouched by this -- they point into the
     * original -- so what a mark selects is still exactly what the reader selected.
     */
    private fun condensed(text: String): String {
        val words = StringBuilder()
        var wantsSpace = false
        for (character in text) {
            if (character.isWhitespace()) {
                wantsSpace = words.isNotEmpty()
            } else {
                if (wantsSpace) words.append(' ')
                wantsSpace = false
                words.append(character)
            }
        }
        return words.toString()
    }
}
