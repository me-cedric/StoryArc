package app.storyarc.core.model

/**
 * What copying a local reading list onto a server would actually move.
 *
 * `collections-and-reading-lists`: when a reader wants a local list on a server "the app
 * offers to copy it, and states which entries cannot be included because they do not exist on
 * that server". Two halves, and the second one is the point: this app has no backend and
 * pushes no files anywhere, so a publication the server does not already hold cannot go into
 * one of its lists. It is left behind and named, rather than silently dropped.
 *
 * A value rather than a step inside the copy, because the reader is shown it *before*
 * anything happens -- the count, what the server already has, and what it does not -- and the
 * same answer then decides what is sent. One calculation, looked at twice.
 *
 * iOS's `ListPromotion` is the same value.
 */
data class ListPromotion(
    /**
     * The entries the server already holds, in the list's own order.
     *
     * The order is the list's, not the library's: a reading list's order is its whole
     * meaning, and a copy that arrived in some other order would be a different list.
     */
    val copying: List<String>,
    /**
     * The entries the server does not hold, in the list's own order.
     *
     * Named so the reader can be told which, not merely how many. "Three cannot be copied" is
     * a number; naming them is something a reader can act on.
     */
    val leftBehind: List<String>,
) {
    /** Everything the list holds, both halves together. */
    val total: Int get() = copying.size + leftBehind.size

    /**
     * Whether there is anything to copy at all.
     *
     * False for an empty list, and false for a list of which this server holds nothing --
     * which is an answer to show before the copy, not a failure to report after it.
     */
    val isPossible: Boolean get() = copying.isNotEmpty()

    companion object {
        fun of(entries: List<String>, heldByServer: (String) -> Boolean): ListPromotion {
            val (copying, leftBehind) = entries.partition(heldByServer)
            return ListPromotion(copying, leftBehind)
        }
    }
}
