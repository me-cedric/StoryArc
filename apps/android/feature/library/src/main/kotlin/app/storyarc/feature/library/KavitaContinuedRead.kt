package app.storyarc.feature.library

import androidx.lifecycle.viewModelScope
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.KavitaProgressStore
import java.util.UUID
import kotlinx.coroutines.launch

/**
 * How far a partial source's continued read has gone, for the source detail screen's
 * progress line. Null for a source that is not partial at all.
 */
fun LibraryViewModel.readProgress(sourceId: UUID): SourceReadProgress? = partialSources[sourceId]

/**
 * Seeds [LibraryViewModel.partialSources] from a read's own answer, and starts the
 * continuation for any Kavita source that just became partial.
 *
 * A source already mid-continuation keeps its progress: a pull-to-refresh reads page one
 * again, and page one alone knows nothing past its own first slice -- replacing an entry
 * already at page nine with a fresh "page two" would be the continuation rewinding itself
 * every time the reader pulls down. Here rather than inside `readServers()` because that
 * file is over its line cap and may not grow.
 *
 * @param opdsCursors the `next` link this read's own first page found for a catalogue that
 *   just turned partial. [SourceReadProgress] has no field for it -- it is Kavita and SMB
 *   shaped, a count and a total -- so a catalogue's own cursor is kept beside it in
 *   [LibraryViewModel.opdsNext] instead of inside it.
 * @param pins carried through to [continueReadingServers], which needs it for an OPDS
 *   catalogue's continuation -- `readServers(pins)` is this function's only caller, and
 *   `11.3` asks the pins a reader already trusted to reach every request a catalogue read
 *   makes, continuation included.
 */
internal fun LibraryViewModel.adoptPartialSources(
    partial: Set<UUID>,
    opdsCursors: Map<UUID, String> = emptyMap(),
    pins: CertificatePins = CertificatePins(),
) {
    for (sourceId in partial) {
        if (partialSources[sourceId] == null) {
            // Exact, not a guess: a page that reported `holdsMore` asked for at most its
            // kind's own limit and got a full page back, by `SourceSlice`'s own rule.
            val firstSliceRead = when (_registry.value.sources.firstOrNull { it.id == sourceId }?.kind) {
                SourceKind.KAVITA_SERVER -> KavitaContributor.FIRST_SLICE
                SourceKind.NETWORK_SHARE -> SmbContributor.FIRST_SLICE
                // A catalogue's first slice is one feed page, whatever size the server
                // chose -- nothing here names that number, so there is no total to divide
                // it into either.
                SourceKind.OPDS_CATALOG, SourceKind.LOCAL_FOLDER, null -> 0
            }
            partialSources = partialSources + (sourceId to SourceReadProgress.started(firstSliceRead))
            opdsCursors[sourceId]?.let { opdsNext = opdsNext + (sourceId to it) }
        }
    }
    partialSources = partialSources.filterKeys { it in partial }
    opdsNext = opdsNext.filterKeys { it in partial }
    smbQueues = smbQueues.filterKeys { it in partial }
    continueReadingServers(pins)
}

/**
 * Starts one background reader per source that is still partial: a Kavita server, a network
 * share or an OPDS catalogue. `sources`' *More from a source than the library holds*: the
 * first slice is what `readServers()` already reads; this is the rest of it, page by page,
 * so the first screen paints from the slice and the library keeps growing underneath it
 * rather than the reader waiting on a server with forty thousand series, a share with a
 * hundred thousand files, or a catalogue a thousand pages deep.
 */
internal fun LibraryViewModel.continueReadingServers(pins: CertificatePins) {
    for (source in _registry.value.sources) {
        if (source.kind != SourceKind.KAVITA_SERVER) continue
        if (partialSources[source.id] == null) continue
        val page = KavitaPage.of(source, credentials) ?: continue
        viewModelScope.launch { continueReadingKavita(source, KavitaClient(page.address)) }
    }
    continueReadingShares()
    continueReadingCatalogues(pins)
}

/**
 * Reads one Kavita source's continuation until it finishes or a page refuses.
 *
 * **Stops and resumes cleanly when the source becomes unreachable.** A page that throws
 * returns without touching [LibraryViewModel.partialSources], so the very next call --
 * another [continueReadingServers], most often from the next `readServers()` -- asks for
 * the same page again rather than skipping it or losing the source's place.
 */
private suspend fun LibraryViewModel.continueReadingKavita(source: Source, client: KavitaClient) {
    // Learned once and kept beside the read count for as long as the source stays partial:
    // an unfiltered listing is proven to answer the server's whole series list in one
    // request, so this costs one request for a number the reader would otherwise never see
    // until the read finished.
    if (partialSources[source.id]?.total == null) {
        val all = runCatching { client.series() }.getOrNull()
        if (all != null) {
            partialSources[source.id]?.let { partialSources = partialSources + (source.id to it.copy(total = all.size)) }
        }
    }
    val kavita = KavitaProgressStore.open(getApplication())
    readOnward(
        progress = { partialSources[source.id] },
        fetch = { page -> runCatching { KavitaContributor.page(source.id, client, page, kavita) }.getOrNull() },
        land = { page, step -> land(source.id, page, step) },
    )
}

/**
 * Merges one page into the library and into the shelf snapshot, and stores where the read
 * now stands.
 *
 * The snapshot is written here as well as by `readServers()`, because a page merged only in
 * memory is gone at the next launch -- the task asks for each page in "the library and the
 * shelf snapshot as it arrives". It does not claim the shelf is fresh, for the reason
 * `readServers()` gives for its own write.
 */
private fun LibraryViewModel.land(sourceId: UUID, page: KavitaContributor.Page, step: SourceReadStep) {
    page.slice.publications.forEach { adopt(it, sourceId) }
    partialSources = when (step) {
        is SourceReadStep.Continuing -> partialSources + (sourceId to step.progress)
        else -> partialSources - sourceId
    }
    rebuild()
    cacheLibrary(claimsFreshness = false)
}

/**
 * The continuation loop: ask for the next page, fold its answer in, and stop at a short
 * page, a refused page, or a page another reader already took.
 *
 * The progress is read again after the page arrives, not carried across the wait. Two
 * readers of one source overlap whenever a `readServers()` starts while a continuation is
 * mid-page, and the second answer for the same page is stale only when it is compared with
 * the progress as it stands now. Compared with the progress it started from, it always
 * matched, so both readers folded every page in and a finished read could come back as
 * partial. A test reaches this through [fetch] and [land], without a server.
 */
internal suspend fun readOnward(
    progress: () -> SourceReadProgress?,
    fetch: suspend (page: Int) -> KavitaContributor.Page?,
    land: (KavitaContributor.Page, SourceReadStep) -> Unit,
) {
    while (true) {
        val requested = progress()?.nextPage ?: return
        val page = fetch(requested) ?: return
        val step = progress()?.advancing(requested, page.seriesRead, page.slice.holdsMore) ?: return
        if (step is SourceReadStep.Stale) return
        land(page, step)
        if (step is SourceReadStep.Finished) return
    }
}
