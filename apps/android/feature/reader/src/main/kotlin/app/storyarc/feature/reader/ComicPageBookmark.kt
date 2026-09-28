package app.storyarc.feature.reader

import app.storyarc.core.model.Annotation
import app.storyarc.core.persistence.AnnotationStore
import java.util.UUID

/**
 * A page bookmark for a fixed-page publication, stored as an [Annotation] -- the same
 * record and the same store PDF marks use (D8). A comic and a scanned PDF have no
 * words to select, so the "highlight" this store otherwise holds is a plain page mark
 * instead: [Annotation.text] names the page rather than quoting it.
 *
 * A locator of its own rather than a PDF's JSON one: the two never meet in one
 * publication's list (a file is one format or the other), and a page index needs none
 * of a text selection's rectangles. iOS's `ComicPageBookmark` is the same shape.
 */
internal object ComicPageBookmark {
    /** The [Annotation] a bookmark of [index] becomes. [pageLabel] is the same "Page N"
     * formatter the PDF marks already use, reused rather than duplicated. */
    fun annotation(index: Int, pageCount: Int, pageLabel: (Int) -> String): Annotation =
        Annotation(
            id = UUID.randomUUID().toString(),
            locator = index.toString(),
            resource = index.toString(),
            progression = progression(index, pageCount),
            chapter = "",
            text = pageLabel(index),
            createdAtEpochMillis = System.currentTimeMillis(),
        )

    /** How far through the publication [index] falls, for [app.storyarc.core.model.inReadingOrder]. */
    fun progression(index: Int, pageCount: Int): Double {
        if (pageCount <= 1) return 0.0
        return (index.toDouble() / (pageCount - 1)).coerceIn(0.0, 1.0)
    }

    /** The page a bookmark's own locator names, or `null` for one this format did not write. */
    fun pageIndexOf(annotation: Annotation): Int? = annotation.locator.toIntOrNull()

    /** Whether [pageIndex] already carries one of [annotations]. */
    fun isBookmarked(pageIndex: Int, annotations: List<Annotation>): Boolean =
        annotations.any { pageIndexOf(it) == pageIndex }

    /** Bookmarks [pageIndex], unless it already carries one -- a reader who presses the
     * row twice on the same page gets one bookmark, not two. */
    fun add(
        pageIndex: Int,
        pageCount: Int,
        store: AnnotationStore?,
        publication: String,
        pageLabel: (Int) -> String,
    ) {
        if (store == null || pageCount <= 0) return
        if (isBookmarked(pageIndex, store.annotations(publication))) return
        store.save(annotation(pageIndex, pageCount, pageLabel), publication)
    }
}
