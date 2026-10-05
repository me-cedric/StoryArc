package app.storyarc.feature.library

import androidx.lifecycle.viewModelScope
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.KavitaFailedSeriesStore
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.SourceReadProgressStore
import app.storyarc.core.persistence.StoredSourceProgress
import java.util.UUID
import kotlinx.coroutines.launch

/**
 * [SourceReadProgress] as [SourceReadProgressStore] keeps it on disk, with the cursor the
 * source's own continuation asks its next page by. A Kavita server has none: its page number
 * is already in the progress.
 */
internal fun SourceReadProgress.stored(opdsNext: String? = null, smbQueue: List<String>? = null) =
    StoredSourceProgress(read, total, nextPage, opdsNext, smbQueue)

/** [StoredSourceProgress] as the continuation loop keeps it in memory. */
private fun StoredSourceProgress.live() = SourceReadProgress(read, total, nextPage)

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
 * **A source new to this process, but not new to the device, resumes from
 * [SourceReadProgressStore] rather than from [SourceReadProgress.started].** Before this
 * store existed, [partialSources] held the only copy of where a continuation stood, so a
 * relaunch forgot it and every source paid for its whole continuation again from page two --
 * `sources`' *More from a source than the library holds* asks for progress that survives
 * exactly that. [resumable] holds the one exception: a record with no cursor for a source
 * kind that continues by one.
 *
 * @param opdsCursors the `next` link this read's own first page found for a catalogue that
 *   just turned partial. [SourceReadProgress] has no field for it -- it is Kavita and SMB
 *   shaped, a count and a total -- so a catalogue's own cursor is kept beside it in
 *   [LibraryViewModel.opdsNext] instead of inside it.
 * @param smbFrontiers the folders this read's own first page of a share had not reached yet,
 *   kept in [LibraryViewModel.smbQueues] for the same reason. Without it the first
 *   continuation page fell back to the share's root and adopted that root's rows a second
 *   time -- see [ServerLibrary.Reading.smbQueues].
 * @param pins carried through to [continueReadingServers], which needs it for an OPDS
 *   catalogue's continuation -- `readServers(pins)` is this function's only caller, and
 *   `11.3` asks the pins a reader already trusted to reach every request a catalogue read
 *   makes, continuation included.
 */
internal fun LibraryViewModel.adoptPartialSources(
    partial: Set<UUID>,
    opdsCursors: Map<UUID, String> = emptyMap(),
    smbFrontiers: Map<UUID, List<String>> = emptyMap(),
    pins: CertificatePins = CertificatePins(),
) {
    val store = SourceReadProgressStore.open(getApplication())
    for (sourceId in partial) {
        if (partialSources[sourceId] == null) {
            val resumed = resumable(sourceId, store)
            partialSources = partialSources + (sourceId to (resumed?.live() ?: SourceReadProgress.started(firstSliceFor(sourceId))))
            // The stored cursor outranks this read's own: the first page always hands back
            // the link to page two, and the record says where the continuation actually
            // stopped. Either beats nothing, which is what a share had before 22.1.
            (resumed?.opdsNext ?: opdsCursors[sourceId])?.let { opdsNext = opdsNext + (sourceId to it) }
            (resumed?.smbQueue ?: smbFrontiers[sourceId])?.let { smbQueues = smbQueues + (sourceId to it) }
        }
    }
    // A source this read did not report partial has either finished (land() already cleared
    // its entry, store included) or is gone from the registry altogether -- either way
    // nothing should keep asking disk about it.
    val known = _registry.value.sources.map { it.id }.toSet()
    val failedStore = KavitaFailedSeriesStore.open(getApplication())
    for (sourceId in partialSources.keys - partial) {
        store.clear(sourceId)
        // Only for a source the registry has let go. A source that merely finished its read
        // may still owe a series, and [retryFailedKavitaSeries] asks for it on every read
        // after that -- clearing here would be the one thing that makes a failed series
        // lost for good again.
        if (sourceId !in known) failedStore.clear(sourceId)
    }
    partialSources = partialSources.filterKeys { it in partial }
    opdsNext = opdsNext.filterKeys { it in partial }
    smbQueues = smbQueues.filterKeys { it in partial }
    continueReadingServers(pins)
    retryFailedKavitaSeries()
}

/**
 * The record a source's continuation may carry on from, or null when it has to start over.
 *
 * A Kavita page number answers for itself, but a share resumes from a folder queue and a
 * catalogue from a feed link. A record written before [StoredSourceProgress] carried those
 * cursors has the counter and not the cursor, and resuming at page five with no cursor would
 * walk the share's root again -- the very read this store exists to spare the reader. Such a
 * record is refused, and the source starts from its first slice instead.
 */
private fun LibraryViewModel.resumable(sourceId: UUID, store: SourceReadProgressStore): StoredSourceProgress? {
    val stored = store.progress(sourceId) ?: return null
    return when (_registry.value.sources.firstOrNull { it.id == sourceId }?.kind) {
        SourceKind.NETWORK_SHARE -> stored.takeIf { it.smbQueue != null }
        SourceKind.OPDS_CATALOG -> stored.takeIf { it.opdsNext != null }
        else -> stored
    }
}

/**
 * Exact, not a guess: a page that reported `holdsMore` asked for at most its kind's own
 * limit and got a full page back, by [SourceSlice]'s own rule.
 */
private fun LibraryViewModel.firstSliceFor(sourceId: UUID): Int =
    when (_registry.value.sources.firstOrNull { it.id == sourceId }?.kind) {
        SourceKind.KAVITA_SERVER -> KavitaContributor.FIRST_SLICE
        SourceKind.NETWORK_SHARE -> SmbContributor.FIRST_SLICE
        // A catalogue's first slice is one feed page, whatever size the server chose --
        // nothing here names that number, so there is no total to divide it into either.
        SourceKind.OPDS_CATALOG, SourceKind.LOCAL_FOLDER, null -> 0
    }

/**
 * Gives every Kavita series that failed an earlier page one more try, on every read rather
 * than only while its source is still paging.
 *
 * A series can fail after its source's continuation has already finished -- the page it was
 * on reached the end and moved [partialSources] on -- and `continueReadingServers()` only
 * drives a source this map still holds. Running here instead, from the same place that
 * seeds a fresh continuation, means a failed series keeps getting asked for on every launch
 * and every pull, which is what keeps task 22.1's own correction true: "still lost until the
 * next full read" stops being true the moment there is always a next one.
 */
internal fun LibraryViewModel.retryFailedKavitaSeries() {
    val failedStore = KavitaFailedSeriesStore.open(getApplication())
    for (source in _registry.value.sources) {
        if (source.kind != SourceKind.KAVITA_SERVER) continue
        val pending = failedStore.pending(source.id)
        if (pending.isEmpty()) continue
        val page = KavitaPage.of(source, credentials) ?: continue
        viewModelScope.launch {
            val kavita = KavitaProgressStore.open(getApplication())
            val result = KavitaContributor.retry(source.id, KavitaClient(page.address), pending, kavita)
            if (result.publications.isNotEmpty()) {
                result.publications.forEach { adopt(it, source.id) }
                rebuild()
                cacheLibrary(claimsFreshness = false)
            }
            val stillFailed = result.stillFailed.toSet()
            if (stillFailed != pending) failedStore.record(source.id, stillFailed)
        }
    }
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
            partialSources[source.id]?.let {
                val withTotal = it.copy(total = all.size)
                partialSources = partialSources + (source.id to withTotal)
                SourceReadProgressStore.open(getApplication()).record(source.id, withTotal.stored())
            }
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
 * Merges one page into the library and into the shelf snapshot, stores where the read now
 * stands, and remembers any series this page could not read so [retryFailedKavitaSeries]
 * gets another chance at it.
 *
 * The snapshot is written here as well as by `readServers()`, because a page merged only in
 * memory is gone at the next launch -- the task asks for each page in "the library and the
 * shelf snapshot as it arrives". It does not claim the shelf is fresh, for the reason
 * `readServers()` gives for its own write.
 *
 * Progress is written to [SourceReadProgressStore] here, not only kept in
 * [LibraryViewModel.partialSources]: this is the one place every page this source's
 * continuation ever lands passes through, continuing or finished alike.
 */
private fun LibraryViewModel.land(sourceId: UUID, page: KavitaContributor.Page, step: SourceReadStep) {
    page.slice.publications.forEach { adopt(it, sourceId) }
    if (page.failedSeriesIds.isNotEmpty()) {
        val failedStore = KavitaFailedSeriesStore.open(getApplication())
        failedStore.record(sourceId, failedStore.pending(sourceId) + page.failedSeriesIds)
    }
    val store = SourceReadProgressStore.open(getApplication())
    partialSources = when (step) {
        is SourceReadStep.Continuing -> {
            store.record(sourceId, step.progress.stored())
            partialSources + (sourceId to step.progress)
        }
        else -> {
            store.clear(sourceId)
            partialSources - sourceId
        }
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
