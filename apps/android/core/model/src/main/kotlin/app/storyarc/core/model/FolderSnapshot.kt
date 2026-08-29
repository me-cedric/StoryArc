package app.storyarc.core.model

/**
 * What a folder held the last time it was looked at.
 *
 * `local-library` requires the app to "detect changes to a folder library without a full
 * rescan", and to reconcile "by comparing file modification times and sizes rather than
 * re-reading every archive". Those two sentences are this type. A walk that reads only
 * directory entries is cheap; comparing one against the last one says exactly which files
 * have to be opened, and opening a file is the expensive part.
 *
 * Pure, and identical on iOS. It is the arithmetic of noticing a change, not the mechanism
 * of being told about one -- the mechanisms have nothing in common between the two platforms
 * and this has to.
 */
data class FolderSnapshot(val entries: Map<String, Entry> = emptyMap()) {

    /**
     * One publication, as a directory listing describes it.
     *
     * The modification time and the size together, because either alone misses a real case:
     * a file replaced with one of the same length keeps its size, and a file copied back
     * from a backup keeps its time.
     *
     * @param path what the library knows the file by -- a filesystem path, or the document
     *   `Uri` of a file inside a picked folder, which is what its identity carries.
     */
    data class Entry(val path: String, val modifiedAtEpochMillis: Long, val size: Long)

    /** What has to be done to catch up with a fresh walk. */
    data class Change(
        /** Files that were not there before. */
        val added: List<Entry> = emptyList(),
        /** Files whose modification time or size has moved. */
        val changed: List<Entry> = emptyList(),
        /** Files that have gone. Their rows go with them. */
        val removed: List<String> = emptyList(),
    ) {
        val isEmpty: Boolean get() = added.isEmpty() && changed.isEmpty() && removed.isEmpty()

        /** The only files that have to be opened, which is the whole point of comparing. */
        val toIndex: List<Entry> get() = added + changed
    }

    /**
     * What changed since this snapshot, or null when the walk cannot be believed.
     *
     * Null for a walk that found nothing at all where something used to be. A folder whose
     * permission has gone stale, or a provider that has not finished mounting, walks as empty
     * -- and reading that as "the reader deleted every book" empties their library. Refusing
     * is the safe answer: a reader who really did empty the folder still has a full rescan,
     * and a reader whose provider was slow keeps their library.
     */
    fun change(walked: List<Entry>): Change? {
        if (walked.isEmpty() && entries.isNotEmpty()) return null

        val added = mutableListOf<Entry>()
        val changed = mutableListOf<Entry>()
        for (entry in walked) {
            val known = entries[entry.path]
            when {
                known == null -> added += entry
                known != entry -> changed += entry
            }
        }
        val seen = walked.mapTo(mutableSetOf()) { it.path }
        // Sorted, so a reconcile does the same thing twice given the same folder -- a map's
        // order is not one, and a test that asserted on it would flake.
        return Change(added, changed, entries.keys.filterNot { it in seen }.sorted())
    }

    /**
     * The snapshot a walk leaves behind.
     *
     * The second half of the same guard as [change]: a walk that found nothing where
     * something used to be leaves the snapshot alone. Overwriting it would throw away the
     * only record of what the folder held, so the pass after the provider came back would see
     * every file as new and re-read every archive.
     */
    fun updated(walked: List<Entry>): FolderSnapshot =
        if (walked.isEmpty() && entries.isNotEmpty()) this else of(walked)

    companion object {
        fun of(entries: List<Entry>): FolderSnapshot =
            FolderSnapshot(entries.associateBy { it.path })
    }
}
