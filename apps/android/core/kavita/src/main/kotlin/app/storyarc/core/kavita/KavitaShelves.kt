package app.storyarc.core.kavita

import kotlinx.serialization.Serializable

/**
 * A collection the server holds.
 *
 * Kavita calls this a tag. It groups series and has no order, which is what separates it
 * from a reading list -- a distinction worth keeping, because a client that treats them
 * alike is a client that will lose someone's order.
 */
@Serializable
data class KavitaCollection(
    val id: Int,
    val title: String = "",
    val summary: String? = null,
)

/** A reading list the server holds: an ordered run of chapters. */
@Serializable
data class KavitaReadingList(
    val id: Int,
    val title: String = "",
    val summary: String? = null,
)

/** One entry in a server reading list, in the order the server keeps. */
@Serializable
data class KavitaReadingListItem(
    val id: Int = 0,
    val order: Int = 0,
    val seriesId: Int = 0,
    val chapterId: Int = 0,
    val title: String? = null,
    val seriesName: String? = null,
) {
    /** What to call it in a list. The chapter's own title, or the series it belongs to. */
    val displayName: String
        get() = title?.takeIf { it.isNotEmpty() } ?: seriesName.orEmpty()
}

/** What `update-by-multiple` wants: a list, a series, and the chapters to append. */
@Serializable
data class KavitaListAppend(
    val readingListId: Int,
    val seriesId: Int,
    val chapterIds: List<Int>,
)
