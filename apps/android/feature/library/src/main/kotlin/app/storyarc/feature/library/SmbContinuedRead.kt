package app.storyarc.feature.library

import androidx.lifecycle.viewModelScope
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.smb.SmbAddress
import app.storyarc.core.smb.SmbClient
import java.util.UUID
import kotlinx.coroutines.launch

/**
 * Continues a network share's walk past its first slice -- the twin of
 * `KavitaContinuedRead.continueReadingKavita` for a source with no page number of its own,
 * only a frontier of folders not yet listed.
 *
 * `sources`' *More from a source than the library holds*: the first slice is what
 * `readServers()` already reads (`SmbContributor.FIRST_SLICE`); this is the rest of the
 * share's walk, continued from [LibraryViewModel.smbQueues] -- the folders [SmbContributor]
 * had not reached yet -- rather than restarted at the share's root on every page, which a
 * share with more folders than `SmbContributor.MAX_FOLDERS` could never walk past.
 */
internal fun LibraryViewModel.continueReadingShares() {
    for (source in _registry.value.sources) {
        if (source.kind != SourceKind.NETWORK_SHARE) continue
        if (partialSources[source.id] == null) continue
        val page = SmbPage.of(source, credentials) ?: continue
        viewModelScope.launch { continueReadingShare(source, SmbClient(page.address), page.address) }
    }
}

/**
 * Reads one share's continuation until it finishes or a page refuses.
 *
 * **Stops and resumes cleanly when the source becomes unreachable.** A page that throws
 * returns without touching [LibraryViewModel.partialSources] or [LibraryViewModel.smbQueues],
 * so the very next [continueReadingShares] asks for the same frontier again rather than
 * losing the share's place -- the same contract `continueReadingKavita` keeps for a server.
 */
private suspend fun LibraryViewModel.continueReadingShare(source: Source, client: SmbClient, address: SmbAddress) {
    readSourceOnward(
        progress = { partialSources[source.id] },
        cursor = { smbQueues[source.id] ?: listOf(address.path) },
        fetch = { queue ->
            runCatching { SmbContributor.page(source.id, client, address, queue) }.getOrNull()
                ?.let { it.slice to it.queue }
        },
        advance = { queue -> smbQueues = smbQueues + (source.id to queue) },
        land = { slice, step ->
            landContinuedSlice(source.id, slice, step)
            if (step !is SourceReadStep.Continuing) smbQueues = smbQueues - source.id
        },
    )
}

/**
 * Merges one continued page into the library and into the shelf snapshot, and stores where
 * the read now stands. Shared by the share and the catalogue continuations -- both land a
 * plain [SourceSlice] rather than a source-specific page type, unlike Kavita's own
 * `KavitaContinuedRead.land`, which still needs the chapter list underneath its page.
 */
internal fun LibraryViewModel.landContinuedSlice(sourceId: UUID, slice: SourceSlice, step: SourceReadStep) {
    slice.publications.forEach { adopt(it, sourceId) }
    partialSources = when (step) {
        is SourceReadStep.Continuing -> partialSources + (sourceId to step.progress)
        else -> partialSources - sourceId
    }
    rebuild()
    cacheLibrary(claimsFreshness = false)
}
