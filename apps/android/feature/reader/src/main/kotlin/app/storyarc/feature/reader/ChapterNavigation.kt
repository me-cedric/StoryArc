package app.storyarc.feature.reader

/**
 * Where the previous or next chapter action goes: within the publication first, and
 * only past its first or last chapter to a neighbouring publication.
 *
 * Decision D4: chapter markers are `ComicInfo`'s `Bookmark` pages — Android has no PDF
 * outline (ADR-0012), so this is `ComicInfo` alone. A plain object, so
 * `ChapterNavigationTest` can drive it with plain numbers — the same reason
 * `EarlyPageTallness` is split out. iOS's `ChapterNavigation` asserts the same table.
 */
internal object ChapterNavigation {
    /** The nearest chapter start before [index], or `null` at or before the first —
     * which is when the previous-chapter action opens a neighbouring publication. */
    fun previousStart(index: Int, starts: List<Int>): Int? = starts.filter { it < index }.maxOrNull()

    /** The nearest chapter start after [index], or `null` at or after the last —
     * which is when the next-chapter action opens a neighbouring publication. */
    fun nextStart(index: Int, starts: List<Int>): Int? = starts.filter { it > index }.minOrNull()
}
