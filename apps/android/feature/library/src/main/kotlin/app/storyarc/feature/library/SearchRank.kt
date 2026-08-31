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
     * 4. The folded title, compared **code point by code point**, so two rows that are equal
     *    by every other key still have one fixed order rather than whichever one the answerer
     *    happened to send first — and the same fixed order on both platforms. Kotlin's
     *    `compareTo` orders by UTF-16 unit and Swift's `<` by scalar, which disagree the
     *    moment a title outside the basic plane meets one inside it: a leading surrogate is
     *    `0xD800`-something and sorts under `U+E000` and above, where the scalar it stands
     *    for sorts over both.
     */
    fun ordered(rows: List<FoundRow>, term: String): List<FoundRow> {
        val needle = fold(term)
        // Scored once per row rather than inside the comparator: a sort asks the comparator
        // O(n log n) times, and folding a string is the expensive half of this.
        return rows
            .map { row -> row to key(row, needle) }
            .sortedWith { left, right -> compare(left.second, right.second) }
            .map { it.first }
    }

    /**
     * Everything the order depends on, computed once.
     *
     * The title is kept as its code points and never as a `String`, because both remaining
     * keys are counts and comparisons over them. Kotlin counts a surrogate pair as two UTF-16
     * units where Swift counts a grapheme cluster as one, and the two order strings
     * differently as well — a title with an astral character or a flag emoji would land in a
     * different place on each platform. Code points are the one unit both agree on, and this
     * is the kind of silent mirror drift this project has already been bitten by once, in
     * natural sort.
     */
    private class Key(
        val strength: Strength,
        val isHeld: Boolean,
        val title: IntArray,
    )

    private fun key(row: FoundRow, needle: String): Key {
        val title = fold(row.result.title)
        return Key(
            strength = strength(title, needle),
            isHeld = row.result.publicationId != null,
            title = title.codePoints().toArray(),
        )
    }

    /** The four keys, in order. iOS's `SearchRank.less` compares the same four. */
    private fun compare(left: Key, right: Key): Int {
        if (left.strength != right.strength) return left.strength.compareTo(right.strength)
        if (left.isHeld != right.isHeld) return if (left.isHeld) -1 else 1
        if (left.title.size != right.title.size) {
            return left.title.size.compareTo(right.title.size)
        }
        for (index in left.title.indices) {
            if (left.title[index] != right.title[index]) {
                return left.title[index].compareTo(right.title[index])
            }
        }
        return 0
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
     * Case and accents removed, and nothing else, so "Café" answers "cafe" and "CAFE".
     *
     * Three steps in this order: decompose, drop the non-spacing marks, lower-case without a
     * locale. NFD rather than NFKD, so the "ﬁ" ligature and a fullwidth letter are left as
     * they are — iOS reaches the same answer with the same three steps, and a compatibility
     * decomposition here would be a fourth thing one platform did and the other did not.
     *
     * [Locale.ROOT] rather than the reader's: this is a comparison key, not a sort the reader
     * reads, and a locale-sensitive fold would make the same two rows compare differently on
     * two devices — Turkish alone would see to that. Alphabetical *display* order is
     * `LibraryIndex.arrange`'s job and does use the reader's collation.
     *
     * iOS's `SearchRank.fold` performs the same three steps, and its own doc comment records
     * why it does not use `String.folding(options:)`, which would have turned "Straße" into
     * "strasse" where Kotlin cannot. The mirrored tests hold both to the same table.
     */
    fun fold(value: String): String =
        Normalizer.normalize(trimmed(value), Normalizer.Form.NFD)
            .replace(COMBINING_MARKS, "")
            .lowercase(Locale.ROOT)

    /**
     * The value with its surrounding blank space removed, by a rule both platforms spell out
     * rather than inherit.
     *
     * `String.trim` and iOS's `CharacterSet.whitespacesAndNewlines` are *not* the same set:
     * `Character.isWhitespace` is false for the non-breaking spaces `U+00A0`, `U+2007` and
     * `U+202F`, which Foundation trims. A term pasted with a leading non-breaking space —
     * which is what a copy out of a web page or a PDF often is — would then land in a
     * different strength tier on each platform.
     *
     * So the set is named here instead of borrowed: every separator, and the control
     * characters that end a line. iOS's `SearchRank.trimmed` names the same one.
     */
    private fun trimmed(value: String): String = value.trim(::isBlank)

    private fun isBlank(character: Char): Boolean = when (Character.getType(character)) {
        Character.SPACE_SEPARATOR.toInt(),
        Character.LINE_SEPARATOR.toInt(),
        Character.PARAGRAPH_SEPARATOR.toInt(),
        -> true
        else -> character.code in 0x09..0x0D || character.code == 0x85
    }

    private val NOT_A_WORD = Regex("[^\\p{L}\\p{N}]+")
    private val COMBINING_MARKS = Regex("\\p{Mn}+")
}
