package app.storyarc.feature.library

/**
 * The continuation loop a network share and an OPDS catalogue share: ask for the next page
 * by its own cursor, fold its answer in, and stop at a short page, a refused page, or a page
 * another reader already took.
 *
 * The twin of `readOnward`, generalised over a cursor [C] instead of a page number -- a
 * share continues from the folder queue its last page left ([SmbContributor.Page.queue])
 * and a catalogue from the feed link its last page named ([OpdsContributor.Page.next]), and
 * neither is "page 2" the way a Kavita request is. `SourceReadProgress.nextPage` still
 * counts rounds for the staleness check both loops share; it is just not what either of
 * these two asks a server for.
 *
 * A free function beside the view model rather than logic inside the coroutine that calls
 * it, so a test can assert all four of its answers without a server -- `ContinuedReadLoopTest`
 * is that reach, the same way `KavitaContinuedReadTest` reaches `readOnward`.
 */
internal suspend fun <C> readSourceOnward(
    progress: () -> SourceReadProgress?,
    cursor: () -> C,
    fetch: suspend (C) -> Pair<SourceSlice, C>?,
    advance: (C) -> Unit,
    land: (SourceSlice, SourceReadStep) -> Unit,
) {
    while (true) {
        val requested = progress()?.nextPage ?: return
        val (slice, nextCursor) = fetch(cursor()) ?: return
        val step = progress()?.advancing(requested, slice.publications.size, slice.holdsMore) ?: return
        if (step is SourceReadStep.Stale) return
        advance(nextCursor)
        land(slice, step)
        if (step is SourceReadStep.Finished) return
    }
}
