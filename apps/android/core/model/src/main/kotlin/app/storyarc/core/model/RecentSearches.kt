package app.storyarc.core.model

/**
 * What the reader searched for lately, most recent first.
 *
 * `library-browsing`: "when a user opens search, recent queries are offered, and
 * can be cleared". A value with its own rules rather than a list in the view
 * model, because those rules — trim, fold duplicates, cap the list — have to come
 * out the same on both platforms, and that is only worth trusting when the same
 * table is put to both (ADR-0001). iOS's `RecentSearches` mirrors it.
 */
data class RecentSearches(val terms: List<String> = emptyList()) {

    val isEmpty: Boolean get() = terms.isEmpty()

    /**
     * The list with [term] at the front.
     *
     * Duplicates fold case-insensitively and the newest spelling wins: someone who
     * searched "Bone" and then "bone" made one search, and two rows that read the
     * same would look like a bug rather than like history.
     *
     * Called once per keystroke, which the folding below is what makes safe: a term
     * that is only whitespace changes nothing, and a term that is the same search
     * half-typed collapses into the one already there.
     */
    fun recording(term: String): RecentSearches {
        val trimmed = term.trim()
        if (trimmed.isEmpty()) return this

        var kept = terms
        // Typing and backspacing is one search, not one per keystroke. A term the
        // newest entry differs from only by how much of it had been typed is that
        // same search, and the longer spelling is the one the reader meant — which
        // is what stops a reader who deletes "manga" back to nothing from filing an
        // "m" they never searched for.
        val newest = kept.firstOrNull()
        if (newest != null && newest.isPrefixOrExtensionOf(trimmed)) {
            if (newest.length >= trimmed.length) return this
            kept = kept.drop(1)
        }
        kept = kept.filterNot { it.equals(trimmed, ignoreCase = true) }
        return RecentSearches((listOf(trimmed) + kept).take(LIMIT))
    }

    /**
     * Whether one of the two strings is the start of the other, ignoring case.
     *
     * The test for "these are two moments of the same typed search" rather than two
     * searches. Case-insensitive because the keyboard's own capitalisation is not a
     * decision the reader made.
     */
    private fun String.isPrefixOrExtensionOf(other: String): Boolean =
        startsWith(other, ignoreCase = true) || other.startsWith(this, ignoreCase = true)

    companion object {
        /**
         * How many are kept.
         *
         * Enough to cover an evening of looking, short enough that the list under a
         * search field stays something a reader reads rather than scrolls.
         */
        const val LIMIT = 8
    }
}
