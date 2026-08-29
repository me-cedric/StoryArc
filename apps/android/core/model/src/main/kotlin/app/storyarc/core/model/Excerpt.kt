package app.storyarc.core.model

/**
 * A little of the text at a place in a publication.
 *
 * `ebook-reader` requires a bookmark to be "saved with its chapter title and a text
 * excerpt". Readium reports text on a locator that came from a search or a selection, and
 * none at all on one that came from a page turn -- which is every locator a bookmark is
 * made from. So the text is taken from the resource instead, at the fraction through it the
 * locator names.
 *
 * A fraction rather than a character offset because that is what a reflowable locator
 * carries: ADR-0006 again, a page break is a function of the reader's type size and is not
 * a position in the document. The fraction is, and it is the same fraction on every device.
 *
 * iOS's `Excerpt` cuts the same strings.
 */
object Excerpt {

    /** Long enough to recognise a passage, short enough for two lines in a list. */
    const val LENGTH: Int = 120

    /**
     * The words at [fraction] through [text].
     *
     * Starts at a word boundary and ends at one, because an excerpt that opens mid-word
     * reads as a bug rather than as a quotation. An empty or blank text gives an empty
     * excerpt, and the row that would have shown it falls back to the chapter title.
     */
    fun at(text: String, fraction: Double, length: Int = LENGTH): String {
        val whole = text.trim()
        if (whole.isEmpty()) return ""

        val start = startOfWord(whole, (whole.length * fraction.coerceIn(0.0, 1.0)).toInt())
        val slice = whole.substring(start, minOf(whole.length, start + length))
        // Only trim the tail back to a boundary when something was actually cut off:
        // the last words of a resource are the whole of what is left, and dropping them
        // to find a space would lose the end of the chapter.
        val cut = if (start + length >= whole.length) slice else slice.substringBeforeLast(' ', slice)
        return cut.trim()
    }

    private fun startOfWord(text: String, index: Int): Int {
        var at = index.coerceIn(0, (text.length - 1).coerceAtLeast(0))
        while (at > 0 && !text[at - 1].isWhitespace()) at--
        return at
    }

    /**
     * The readable text of an XHTML resource.
     *
     * Deliberately not a parser. This is used for one thing -- a hundred and twenty
     * characters shown in a list -- and a resource that defeats it produces a worse
     * excerpt rather than a wrong bookmark.
     *
     * The head goes first, with the scripts and the styles. All three are text to a
     * tag-stripper and none of them is text to a reader: leaving the head in put the
     * `<title>` at the front of every excerpt, so a bookmark in "Chapter Two" quoted the
     * words "Chapter Two" back before reaching a sentence -- seen on an emulator, which is
     * how this rule got written.
     */
    fun plainText(markup: String): String =
        markup
            .replace(HEAD, " ")
            .replace(SCRIPT_OR_STYLE, " ")
            .replace(TAG, " ")
            .let { text -> ENTITIES.entries.fold(text) { acc, (k, v) -> acc.replace(k, v) } }
            .replace(NUMERIC_ENTITY, " ")
            .replace(WHITESPACE, " ")
            .trim()

    private val HEAD =
        Regex("<head\\b[^>]*>.*?</head>", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
    private val SCRIPT_OR_STYLE =
        Regex("<(script|style)\\b[^>]*>.*?</\\1>", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
    private val TAG = Regex("<[^>]*>")
    private val NUMERIC_ENTITY = Regex("&#?\\w+;")
    private val WHITESPACE = Regex("\\s+")
    private val ENTITIES = mapOf(
        "&nbsp;" to " ",
        "&amp;" to "&",
        "&lt;" to "<",
        "&gt;" to ">",
        "&quot;" to "\"",
        "&apos;" to "'",
        "&#39;" to "'",
        "&mdash;" to "—",
        "&ndash;" to "–",
        "&hellip;" to "…",
    )
}
