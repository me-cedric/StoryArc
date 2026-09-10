package app.storyarc.feature.library

/**
 * What a server's `pagesRead` and `pagesTotal` say about one entry of a reading list.
 *
 * Kept apart from the row that draws it so the rule can be asserted without a composition,
 * and so both platforms can state it the same way. iOS's `ServerListProgress` is its twin.
 *
 * The distinction that matters is [State.Unknown] against [State.Unread]. Kavita sends
 * `pagesRead: 0` for both an unread entry and an entry it has no page count for, and
 * `collections-and-reading-lists` asks for nothing to be claimed in the second case: "the
 * entry states nothing rather than an assumed zero, and the list's own count of finished
 * entries excludes it rather than counting it unread". A total of zero is the only honest
 * signal of the difference.
 */
internal object ServerListProgress {

    /** How far into an entry a reader has gone, as the server reports it. */
    sealed interface State {
        /** The server gave no page count, so nothing is known and nothing is said. */
        data object Unknown : State

        /** A known length, none of it read. */
        data object Unread : State

        /** Part of a known length, at [percent] of the way through. */
        data class Part(val percent: Int) : State

        /** Every page of a known length, or more. */
        data object Finished : State
    }

    /** How many of a list's entries are finished, out of the ones it knows about. */
    data class Counted(val finished: Int, val of: Int)

    fun of(pagesRead: Int, pagesTotal: Int): State = when {
        pagesTotal <= 0 -> State.Unknown
        pagesRead <= 0 -> State.Unread
        pagesRead >= pagesTotal -> State.Finished
        // Clamped away from both ends: one page of four hundred is progress a reader made and
        // 0% would deny it, and a page short of the end is not finished.
        else -> State.Part((pagesRead * 100 / pagesTotal).coerceIn(1, 99))
    }

    /** The list's own tally, or null when the server said nothing about any entry. */
    fun summary(entries: List<Pair<Int, Int>>): Counted? {
        val known = entries.map { (read, total) -> of(read, total) }
            .filterNot { it == State.Unknown }
        if (known.isEmpty()) return null
        return Counted(finished = known.count { it == State.Finished }, of = known.size)
    }
}
