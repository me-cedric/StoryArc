package app.storyarc.feature.library

import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.LibraryCache
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Last session's shelf, and the one fact a reader is told about it.
 *
 * `sources` asks for the cached catalogue "within 500 ms of the library view appearing" and
 * for "a single unobtrusive indicator" saying that content is cached and when it was last
 * refreshed. Both halves are here: the snapshot, and the moment it carries.
 *
 * Beside the view model rather than inside it, and for the reason iOS's `LibraryCaching`
 * gives on that side -- the shelf's file is over its line cap, and a policy about a file on
 * disk is a thing in its own right. [LibrarySnapshot] is the decision about *whether* to
 * write; this is what does it and what remembers when.
 */
internal class LibraryShelfCache(private val cache: LibraryCache) {

    private val _cachedAt = MutableStateFlow<Long?>(null)

    /**
     * When the shelf on screen was last confirmed, while it is still the cached one.
     *
     * Null once a walk has finished, because at that point the shelf is not cached -- it is
     * current, and saying otherwise would be the indicator lying quietly in the corner.
     */
    val cachedAt: StateFlow<Long?> = _cachedAt.asStateFlow()

    /** What was on the shelf last time, or null when there is nothing to put back. */
    fun restore(): LibraryCache.Snapshot? =
        cache.read()?.also { _cachedAt.value = it.refreshedAtEpochMillis }

    /**
     * Writes the shelf as it now stands, where [LibrarySnapshot] says it is worth writing.
     *
     * @param partial whether the walk that produced this shelf met something it could not
     *   read. A partial walk has refreshed nothing, so it neither clears the indicator nor
     *   stamps `now` on to disk.
     * @param claimsFreshness whether this write also means the shelf on screen is current.
     *   False for a server read, which happens *beside* the folder walk rather than after
     *   it: the rows it found are worth keeping for the next launch, and saying "not
     *   cached any more" while the walk is still going -- or was partial -- would be the
     *   indicator answering for a question nobody asked it.
     */
    fun write(
        publications: List<Publication>,
        locations: Map<String, String>,
        partial: Boolean,
        claimsFreshness: Boolean = true,
    ) {
        val cached = cache.read()?.publications?.size ?: 0
        if (!LibrarySnapshot.worthWriting(partial, publications.size, cached)) return
        cache.write(
            LibraryCache.Snapshot(
                refreshedAtEpochMillis = System.currentTimeMillis(),
                publications = publications,
                locations = locations,
            ),
        )
        if (claimsFreshness) _cachedAt.value = null
    }

    /** Throws the snapshot away, for a library that really is empty. */
    fun clear() {
        cache.clear()
        _cachedAt.value = null
    }

    /** Forgets the moment without touching the file, for a shelf that has just been edited. */
    fun forgetTheMoment() {
        _cachedAt.value = null
    }
}
