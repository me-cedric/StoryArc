package app.storyarc.core.model

/**
 * One match inside a publication, as a line a reader can read.
 *
 * `ebook-reader`: "matches are listed with surrounding context and tapping one jumps to it".
 * The renderer reports the words on each side of a hit and how much of each it felt like
 * giving; what a list needs is a bounded line with the match still visible in it, and that is
 * what this makes.
 *
 * Its own type rather than three strings passed around, because the trimming has a rule worth
 * stating once and asserting on both platforms: the *match* is what must survive. Trimming
 * the context symmetrically would be the obvious thing and the wrong one -- a hit near the
 * start of a paragraph has almost nothing before it and plenty after, and taking the same
 * number of characters from each side would waste the budget on one and cut the other.
 *
 * iOS's `SearchSnippet` cuts the same strings.
 */
data class SearchSnippet(
    /** What comes before the match, already trimmed. */
    val before: String,
    /** The matched words themselves. Never trimmed. */
    val match: String,
    /** What comes after the match, already trimmed. */
    val after: String,
) {

    /**
     * The whole line, for a reader and for a screen reader.
     *
     * One string rather than three, because TalkBack reading "before, match, after" as three
     * labels is three announcements of one sentence.
     */
    val line: String get() = listOf(before, match, after).filter { it.isNotEmpty() }.joinToString(" ")

    companion object {
        /** How much context a row can hold, either side of the match together. */
        const val BUDGET: Int = 90

        /**
         * Builds a snippet, spending the budget on whichever side has text to spend it on.
         *
         * The match is kept whole even when it alone exceeds the budget: a row that elided
         * the thing the reader searched for would be a row about nothing.
         */
        fun of(before: String, match: String, after: String, budget: Int = BUDGET): SearchSnippet {
            val leading = before.trim()
            val trailing = after.trim()

            // Half each, then whatever the shorter side did not use goes to the longer one.
            val half = maxOf(0, budget) / 2
            val leadingSpare = maxOf(0, half - leading.length)
            val trailingSpare = maxOf(0, half - trailing.length)

            return SearchSnippet(
                before = tail(leading, half + trailingSpare),
                match = match,
                after = head(trailing, half + leadingSpare),
            )
        }

        /** The end of the leading context -- the words nearest the match, not the first ones. */
        private fun tail(text: String, limit: Int): String {
            if (text.length <= limit) return text
            val cut = text.takeLast(limit)
            // Start at a word, so the line does not open mid-word.
            val space = cut.indexOf(' ')
            return if (space < 0) cut else cut.substring(space + 1)
        }

        /** The start of the trailing context -- the words nearest the match. */
        private fun head(text: String, limit: Int): String {
            if (text.length <= limit) return text
            val cut = text.take(limit)
            val space = cut.lastIndexOf(' ')
            return if (space < 0) cut else cut.substring(0, space)
        }
    }
}
