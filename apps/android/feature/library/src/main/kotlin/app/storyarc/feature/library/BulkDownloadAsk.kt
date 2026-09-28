package app.storyarc.feature.library

import app.storyarc.core.model.BulkSelection

/**
 * What a reader is told before a whole shelf is fetched.
 *
 * `collections-and-reading-lists`: downloading a collection or a reading list "states the item
 * count and total size before starting". Both numbers describe the fetch, not the shelf --
 * what is already on the device is neither fetched again nor weighed again, so a reader who
 * has most of a collection already is quoted the megabytes they are about to spend rather than
 * the megabytes the collection occupies.
 *
 * A value beside the menu rather than two lines inside a click handler, because a click
 * handler cannot be asked what it would have said. iOS's `BulkDownloadAsk` answers the same.
 */
data class BulkDownloadAsk(
    /** What would be fetched: the selection, less what the device already holds. */
    val ids: Set<String>,
    /** What those, and only those, weigh. */
    val bytes: Long,
) {
    companion object {
        /**
         * The question to put to the reader, or null when there is nothing to fetch.
         *
         * Null rather than a prompt counting nought: a shelf already on the device gets a
         * sentence saying so, which is a different answer from a confirmation the reader
         * would have to cancel.
         */
        fun of(
            selection: Set<String>,
            onDevice: Set<String>,
            weigh: (Set<String>) -> Long,
        ): BulkDownloadAsk? {
            val ids = BulkSelection.downloading(selection, onDevice)
            if (ids.isEmpty()) return null
            return BulkDownloadAsk(ids, weigh(ids))
        }
    }
}
