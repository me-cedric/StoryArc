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
    /** The cover the server holds for this collection, or null when it has none. */
    val coverImage: String? = null,
    /**
     * Whether a reader chose that cover.
     *
     * **The field a collection did not have, and the branch that was dead without it.**
     * `collections-and-reading-lists` composites a shelf's first four member covers "unless
     * the user sets a specific one", and the app honoured that for a reading list and ignored
     * it for a collection: the model dropped the field, so `chosenCover` was always false and
     * a reader who locked a collection's cover on the server still saw the app's composite.
     * Found by an archive verification on 2026-09-12. The reading list's twin is below, and
     * the two are decoded the same way for the same reason.
     */
    val coverImageLocked: Boolean = false,
)

/** A reading list the server holds: an ordered run of chapters. */
@Serializable
data class KavitaReadingList(
    val id: Int,
    val title: String = "",
    val summary: String? = null,
    /** The cover the server holds for this list, or null when it has none. */
    val coverImage: String? = null,
    /**
     * Whether a reader chose that cover.
     *
     * `collections-and-reading-lists` composites a shelf's first four member covers "unless
     * the user sets a specific one", and this is the server's word for having set one. An
     * older Kavita sends neither field, and the defaults say what that means: nothing chosen,
     * so the app draws its own.
     */
    val coverImageLocked: Boolean = false,
    /** How many entries the server says the list holds, before any of them are fetched. */
    val itemCount: Int = 0,
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
    /** How far into this entry the server says the reader has gone. */
    val pagesRead: Int = 0,
    /**
     * How many pages the entry has, as the server counts them.
     *
     * Zero is the server saying nothing rather than an empty chapter, and
     * `collections-and-reading-lists` asks for nothing to be claimed in that case. It is the
     * only honest signal: `pagesRead` is zero for an unread entry as well.
     */
    val pagesTotal: Int = 0,
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

/** What `create` wants: a name, and nothing else. Kavita fills in the rest. */
@Serializable
data class KavitaListDraft(val title: String)

/**
 * What `update-for-series` wants: a collection, a name for it, and the series to put in it.
 *
 * Zero for the id is Kavita's own way of saying "make one": its bulk-add creates the
 * collection when the id names none. There is no separate create route for a collection the
 * way there is for a reading list.
 */
@Serializable
data class KavitaCollectionDraft(
    val collectionTagId: Int,
    val collectionTagTitle: String,
    val seriesIds: List<Int>,
)

/** What `update-position` wants: one entry, where it is, and where it goes. */
@Serializable
data class KavitaListPosition(
    val readingListId: Int,
    val readingListItemId: Int,
    val fromPosition: Int,
    val toPosition: Int,
)
