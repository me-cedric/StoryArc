package app.storyarc.feature.library

import androidx.lifecycle.viewModelScope
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import kotlinx.coroutines.launch

/**
 * Continues an OPDS catalogue's feed past its first page, by following the feed's own `next`
 * link -- the twin of `SmbContinuedRead.continueReadingShares` for a source with no walk of
 * its own, only a chain of pages the server hands forward one at a time.
 *
 * `sources`' *More from a source than the library holds*: the first slice is one feed page,
 * which `readServers()` already reads; this is the rest of the chain, continued from
 * [LibraryViewModel.opdsNext] -- the `next` link [OpdsContributor] last read -- rather than
 * re-asked for the catalogue's root feed on every page, which would read the same first page
 * forever.
 */
internal fun LibraryViewModel.continueReadingCatalogues(pins: CertificatePins) {
    for (source in _registry.value.sources) {
        if (source.kind != SourceKind.OPDS_CATALOG) continue
        if (partialSources[source.id] == null) continue
        val page = CataloguePage.of(source, credentials) ?: continue
        viewModelScope.launch { continueReadingCatalogue(source, page, pins) }
    }
}

/**
 * Reads one catalogue's continuation until it finishes or a page refuses.
 *
 * **Stops and resumes cleanly when the source becomes unreachable.** A page that throws
 * returns without touching [LibraryViewModel.partialSources] or [LibraryViewModel.opdsNext],
 * so the very next [continueReadingCatalogues] asks for the same link again rather than
 * losing the catalogue's place.
 */
private suspend fun LibraryViewModel.continueReadingCatalogue(
    source: Source,
    page: CataloguePage,
    pins: CertificatePins,
) {
    readSourceOnward(
        progress = { partialSources[source.id] },
        cursor = { opdsNext[source.id] },
        fetch = { url ->
            url?.let { runCatching { OpdsContributor.page(source.id, page, pins, it) }.getOrNull() }
                ?.let { it.slice to it.next }
        },
        advance = { next -> opdsNext = if (next != null) opdsNext + (source.id to next) else opdsNext - source.id },
        land = { slice, step -> landContinuedSlice(source.id, slice, step) },
    )
}
