package app.storyarc.feature.library

/**
 * What a picked folder is called on the sources list.
 *
 * It was called `primary:Audiobooks`. A tree `Uri` from the system picker ends in a
 * *document id*, not a path — `.../tree/primary%3AAudiobooks` decodes to the single segment
 * `primary:Audiobooks`, and the old derivation only cut at a `/`, so the storage volume and
 * its separator went straight onto the screen and into the source's top bar.
 *
 * The provider's own display name comes first, because it is the name the reader chose in
 * the picker and the only one that survives a folder being reached through a document
 * provider that names things differently from its ids. The id is the fallback, cut at both
 * separators; the whole `Uri` is the last resort, so a source is never nameless.
 *
 * Pure, so all four cases are asserted without a `ContentResolver`. The same split
 * [SourceRemoval] makes.
 */
internal object FolderSourceName {

    /**
     * @param displayName what the provider calls the folder, or null when it will not say.
     * @param lastPathSegment the tree `Uri`'s last segment — its root document id.
     * @param locator the whole tree `Uri`, which is what a source is matched on.
     */
    fun of(displayName: String?, lastPathSegment: String?, locator: String): String {
        displayName?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        return lastPathSegment
            ?.substringAfterLast('/')
            ?.substringAfterLast(':')
            ?.takeIf { it.isNotBlank() }
            ?: locator
    }

    /**
     * Whether a source is still carrying the id the old derivation left on it.
     *
     * A reader's own name is never overwritten — `sources` requires a rename to stick — so
     * healing an existing row needs a way to tell the two apart, and the raw document id is
     * exactly the string nobody types. A folder added before this existed gets its name
     * corrected on the next launch; one that was renamed does not.
     */
    fun isRawDocumentId(name: String, lastPathSegment: String?): Boolean =
        lastPathSegment != null && name == lastPathSegment && name != of(null, name, name)
}
