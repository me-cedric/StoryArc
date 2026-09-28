package app.storyarc.feature.library

import androidx.lifecycle.viewModelScope
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
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
 */
internal fun LibraryViewModel.adoptPartialSources(partial: Set<UUID>) {
    for (sourceId in partial) {
        if (partialSources[sourceId] == null) {
            // Exact, not a guess: a page that reported `holdsMore` asked for at most its
            // kind's own limit and got a full page back, by `SourceSlice`'s own rule.
            val firstSliceRead = when (_registry.value.sources.firstOrNull { it.id == sourceId }?.kind) {
                SourceKind.KAVITA_SERVER -> KavitaContributor.FIRST_SLICE
                SourceKind.NETWORK_SHARE -> SmbContributor.FIRST_SLICE
                // A catalogue's first slice is one feed page, whatever size the server
                // chose -- nothing here names that number, and nothing yet continues an
                // OPDS read past it, so there is no total to divide it into either.
                SourceKind.OPDS_CATALOG, SourceKind.LOCAL_FOLDER, null -> 0
            }
            partialSources = partialSources + (sourceId to SourceReadProgress.started(firstSliceRead))
        }
    }
    partialSources = partialSources.filterKeys { it in partial }
    continueReadingServers()
}

/**
 * Starts one background reader per Kavita source that is still partial.
 *
 * `sources`' *More from a source than the library holds*: the first slice is what
 * `readServers()` already reads; this is the rest of it, page by page, so the first screen
 * paints from the slice and the library keeps growing underneath it rather than the reader
 * waiting on a server with forty thousand series.
 *
 * SMB and OPDS are not here yet -- `docs/delivery` names both as still to build.
 */
internal fun LibraryViewModel.continueReadingServers() {
    for (source in _registry.value.sources) {
        if (source.kind != SourceKind.KAVITA_SERVER) continue
        if (partialSources[source.id] == null) continue
        val page = KavitaPage.of(source, credentials) ?: continue
        viewModelScope.launch { continueReadingKavita(source, KavitaClient(page.address)) }
    }
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
    while (true) {
        val progress = partialSources[source.id] ?: return
        val result = runCatching { KavitaContributor.page(source.id, client, progress.nextPage) }.getOrNull() ?: return
        when (val step = progress.advancing(progress.nextPage, result.seriesRead, result.slice.holdsMore)) {
            is SourceReadStep.Stale -> return
            is SourceReadStep.Continuing -> {
                result.slice.publications.forEach { adopt(it, source.id) }
                partialSources = partialSources + (source.id to step.progress)
                rebuild()
            }
            is SourceReadStep.Finished -> {
                result.slice.publications.forEach { adopt(it, source.id) }
                partialSources = partialSources - source.id
                rebuild()
                return
            }
        }
    }
}
