package app.storyarc.feature.library

/**
 * Where a source's continued read stands: how much of it has been merged so far, how much
 * more there is when the count is known, and which page answers next.
 *
 * `sources`' *More from a source than the library holds*: the first read is a slice, and
 * this is what a source keeps between the page that finished it and the page that
 * continues it -- across a pull that starts a second `readServers()` before the first has
 * finished, and across the source going unreachable and coming back. iOS's
 * `SourceReadProgress` is the same shape.
 */
data class SourceReadProgress(
    /**
     * Merged so far. Seeded from the first slice, which the source detail screen already
     * counted before any of this existed.
     */
    val read: Int,
    /**
     * The server's whole count, once it is known. Null reads as "holds more" with no
     * number, which is every source kind's behaviour before this and every kind this does
     * not yet know a total for.
     */
    val total: Int?,
    /** The next page to ask for. */
    val nextPage: Int,
) {
    companion object {
        fun started(firstSliceRead: Int) = SourceReadProgress(read = firstSliceRead, total = null, nextPage = 2)
    }
}

/** What one more page does to a source's progress. */
internal sealed class SourceReadStep {
    /**
     * The page asked for is not the page this progress is waiting on -- a second reader of
     * the same source already moved past it, most often two `readServers()` calls
     * overlapping. Folding this answer in as well would count that page twice.
     */
    object Stale : SourceReadStep()

    /** The server has more after this page. */
    data class Continuing(val progress: SourceReadProgress) : SourceReadStep()

    /** This page was short (or empty): the read reached the end. */
    data class Finished(val progress: SourceReadProgress) : SourceReadStep()
}

/**
 * Folds one page's answer into this progress.
 *
 * A free function beside the type rather than logic inside the coroutine that calls it, so
 * a network-less test suite can assert every one of its three answers directly.
 * `SourceReadProgressTest` is that reach.
 */
internal fun SourceReadProgress.advancing(pageRequested: Int, unitsRead: Int, holdsMore: Boolean): SourceReadStep {
    if (pageRequested != nextPage) return SourceReadStep.Stale
    val merged = copy(read = read + unitsRead, nextPage = nextPage + 1)
    return if (holdsMore) SourceReadStep.Continuing(merged) else SourceReadStep.Finished(merged)
}
