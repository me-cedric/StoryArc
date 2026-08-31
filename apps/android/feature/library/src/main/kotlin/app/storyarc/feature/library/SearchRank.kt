package app.storyarc.feature.library

import java.text.Normalizer
import java.util.Locale

/**
 * How well one row answers the question, and how two rows compare when both do.
 *
 * `library-browsing`, *Mixed local and server search*: "server results and local results are
 * merged into one **ranked** list". A merge that only concatenated would satisfy the word
 * "merged" and not the word "ranked" — the device's index and somebody's server each hand
 * over rows in an order that means something to them and nothing to each other, and laying
 * one after the other is two lists drawn end to end.
 *
 * **Why a local match and a remote match compare the way they do.** Rows are compared on how
 * well the title meets the term *first*, and on where the row lives only when that is a tie.
 * The reader asked for a book, not for a place: a server's exact title beating a folder's
 * loose substring is the right answer, and pushing every remote row under every local one
 * would turn the ranking into a statement about storage. Where two rows answer the question
 * equally well, the one already on the device wins — it opens now and the other needs a
 * network, and that is the only respect in which where it lives is news.
 *
 * **What this deliberately does not do is re-rank the screen.** It orders one answer, as that
 * answer arrives. [SearchListing] appends the result and never sorts again, because the same
 * requirement's next clause is that "the arrival of remote results never reorders or displaces
 * a result the reader is already reaching for". Ranking within an answer is as much ranking as
 * a list that must not move can have.
 *
 * Pure — no network, no clock, no store. iOS's `SearchRank` mirrors it, and both platforms
 * hold the same table of cases against it.
 */
internal object SearchRank {

    /**
     * How close a row's title comes to the term, best first.
     *
     * Five tiers over the title alone. The detail line is a series or an author the local
     * index has already used to decide which heading the row sits under, and a sixth tier
     * reading it again would be the grouping's opinion cast a second time as ranking.
     */
    enum class Strength {
        /** The title *is* the term. */
        EXACT,

        /** The title begins with the term. */
        START,

        /** A word inside the title begins with the term. */
        WORD,

        /** The term is in the title, mid-word. */
        WITHIN,

        /**
         * The title does not contain the term. Whoever answered matched something the row
         * does not show — an author, a tag, a summary this app never saw.
         */
        ELSEWHERE,
    }

    /**
     * One answer, ordered. Ties broken so the order is total and cannot wobble.
     *
     * Four keys, in this order:
     *
     * 1. [Strength] — how well the title meets the term.
     * 2. Held before away, per the note above.
     * 3. The shorter title — "Bone" answers "bone" more completely than "Bone Companion".
     * 4. The folded title, so two rows that are equal by every other key still have one fixed
     *    order rather than whichever one the answerer happened to send first.
     */
    fun ordered(rows: List<FoundRow>, term: String): List<FoundRow> {
        val needle = fold(term)
        // Scored once per row rather than inside the comparator: a sort asks the comparator
        // O(n log n) times, and folding a string is the expensive half of this.
        return rows
            .map { row -> row to key(row, needle) }
            .sortedWith(
                compareBy<Pair<FoundRow, Key>> { it.second.strength }
                    .thenBy { !it.second.isHeld }
                    .thenBy { it.second.length }
                    .thenBy { it.second.title },
            )
            .map { it.first }
    }

    /** Everything the order depends on, computed once. */
    private data class Key(
        val strength: Strength,
        val isHeld: Boolean,
        val length: Int,
        val title: String,
    )

    private fun key(row: FoundRow, needle: String): Key {
        val title = fold(row.result.title)
        return Key(
            strength = strength(title, needle),
            isHeld = row.result.publicationId != null,
            length = title.length,
            title = title,
        )
    }

    /** How well a title meets a term, both already folded. */
    fun strength(foldedTitle: String, foldedTerm: String): Strength {
        // An empty term matches nothing in particular, so every row is equally far from it
        // and the remaining keys decide. Reachable only through a caller that asked before
        // trimming; the search itself never asks an empty question.
        if (foldedTerm.isEmpty()) return Strength.ELSEWHERE
        if (foldedTitle == foldedTerm) return Strength.EXACT
        if (foldedTitle.startsWith(foldedTerm)) return Strength.START
        if (!foldedTitle.contains(foldedTerm)) return Strength.ELSEWHERE
        return if (words(foldedTitle).any { it.startsWith(foldedTerm) }) {
            Strength.WORD
        } else {
            Strength.WITHIN
        }
    }

    /**
     * The title's words, for the word-start tier.
     *
     * Split on everything that is not a letter or a digit, so "Vol.2" is two words and
     * "d'Artagnan" is two — a reader who types "artagnan" has started a word as far as they
     * are concerned.
     */
    private fun words(folded: String): List<String> =
        folded.split(NOT_A_WORD).filter { it.isNotEmpty() }

    /**
     * Case and accents removed, so "Café" answers "cafe" and "CAFE".
     *
     * [Locale.ROOT] rather than the reader's: this is a comparison key, not a sort the reader
     * reads, and a locale-sensitive fold would make the same two rows compare differently on
     * two devices. Alphabetical *display* order is `LibraryIndex.arrange`'s job and does use
     * the reader's collation.
     *
     * iOS's `SearchRank.fold` strips the same two things with `folding(options:)`, and the
     * mirrored tests hold both to the same table.
     */
    fun fold(value: String): String =
        Normalizer.normalize(value.trim(), Normalizer.Form.NFD)
            .replace(COMBINING_MARKS, "")
            .lowercase(Locale.ROOT)

    private val NOT_A_WORD = Regex("[^\\p{L}\\p{N}]+")
    private val COMBINING_MARKS = Regex("\\p{Mn}+")
}
