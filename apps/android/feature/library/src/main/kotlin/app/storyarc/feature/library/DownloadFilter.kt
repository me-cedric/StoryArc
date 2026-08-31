package app.storyarc.feature.library

import app.storyarc.core.model.Publication

/**
 * Whether StoryArc has fetched a publication and is keeping it, as a filter group.
 *
 * `library-browsing` lists **download state** among the facets, and its *Filtering offline*
 * scenario asks that filtering to "Downloaded" show "only publications readable without a
 * network ... regardless of source state".
 *
 * **This is not the availability axis wearing a second name**, though the two are close
 * enough that one of them would otherwise have been redundant.
 * [LibraryAvailability.ON_THIS_DEVICE] keeps everything the app can still open with no
 * network — a folder the reader picked as much as a download the app fetched — because that
 * axis asks *will this open on a plane*. This asks the narrower question `offline-downloads`
 * owns: did **this app** fetch it, and is it keeping it. A file a folder walk found answers
 * yes to the first and no to the second, and the difference is not academic — the card can
 * be pulled, the grant can lapse, the folder can be unmounted, which is what
 * `LibraryScreen`'s unavailable-folders notice exists for. Only a copy in the app's own
 * storage carries `offline-downloads`' promise, which is the same line [isKeptOnDevice]
 * draws for the mark on a cover.
 *
 * So the group admits a subset of what the axis admits, and *Filtering offline*'s clause
 * stays true of it — everything downloaded is readable without a network — while the two
 * controls answer different questions. The spec's own Open Question said as much before
 * either existed: what blocked download state was that "the library is assembled from a scan
 * that never consults" the record of downloaded files. The axis never needed that record.
 * This does.
 *
 * Held beside the library's screens rather than on `LibraryQuery`, exactly as
 * [LibraryAvailability] is: the query is the value both platforms encode, and a case added
 * to it is a change to `:core:model` and to iOS's mirror of it. iOS keeps the same three
 * answers in `LibraryFacets.swift`.
 */
enum class DownloadFilter {
    /**
     * No opinion. Named for what the reader sees rather than for the group being empty: the
     * menu row reads "Downloaded or not", which is what this shows.
     */
    EITHER,

    /** Only what the app fetched and is keeping. */
    DOWNLOADED,

    /** Only what it has not. The question before a journey, rather than during one. */
    NOT_DOWNLOADED,
    ;

    /**
     * Whether the group is narrowing anything.
     *
     * What the filter chip counts and what "Clear filters" has to undo. A group that counted
     * while it was off would make the chip disagree with the shelf.
     */
    val isActive: Boolean get() = this != EITHER

    /**
     * Whether a publication survives the group.
     *
     * The whole rule, in one place, so both platforms can assert the same three cases rather
     * than read them off a menu.
     */
    fun keeps(isDownloaded: Boolean): Boolean = when (this) {
        EITHER -> true
        DOWNLOADED -> isDownloaded
        NOT_DOWNLOADED -> !isDownloaded
    }
}

/**
 * The shelf as this group leaves it.
 *
 * Applied over the view model's already-sorted list rather than inside the query, so ticking
 * the group costs one pass and never a re-sort — the same arrangement [narrowedTo] uses for
 * the availability axis, and for the same reason.
 */
internal fun List<Publication>.narrowedTo(
    downloads: DownloadFilter,
    isDownloaded: (Publication) -> Boolean,
): List<Publication> =
    if (!downloads.isActive) this else filter { downloads.keeps(isDownloaded(it)) }
