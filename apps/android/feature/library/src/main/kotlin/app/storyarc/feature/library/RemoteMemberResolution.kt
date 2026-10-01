package app.storyarc.feature.library

import app.storyarc.core.catalogue.CatalogueAcquisition
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsFeed
import java.util.UUID

/**
 * How [OpdsContributor] names an entry's remote identifier, so a row built from one can be
 * told apart from a Kavita chapter's `"chapter:"`.
 */
private const val OPDS_REMOTE_ID_PREFIX = "opds:"

/**
 * Finding, in a freshly read feed, the one entry a catalogue-only row names.
 *
 * `collections-and-reading-lists`' bulk download "queues them per offline-downloads" for a
 * member with no local file -- a unified-shelf row [OpdsContributor] built with no
 * acquisition URL kept on it. This pins the matching [KeepOffline]'s remote enqueue does the
 * fetch around. iOS's `RemoteMemberResolution` is the same rule.
 */
object RemoteMemberResolution {
    /**
     * [remoteId] as [OpdsContributor] wrote it onto the row's identity, and [feed] as read
     * again from that row's own source. Null for anything that is not an OPDS remote id, or
     * whose entry the feed no longer lists.
     */
    fun opdsEntry(remoteId: String, feed: OpdsFeed): Pair<OpdsEntry, OpdsAcquisition>? {
        if (!remoteId.startsWith(OPDS_REMOTE_ID_PREFIX)) return null
        val entryId = remoteId.removePrefix(OPDS_REMOTE_ID_PREFIX)
        val entry = feed.publications.firstOrNull { it.id == entryId } ?: return null
        val acquisition = CatalogueAcquisition.best(entry) ?: return null
        return entry to acquisition
    }

    /**
     * Queues a resolved member, and returns the id its undo takes back.
     *
     * The queue's id, not the row's: the row is `srv:<source>:opds:<entry>` and the queue
     * keys the download `opds:<source>:<entry>`, so an undo by the row's id took nothing
     * back. Null when the queue already held this download -- the reader queued it before
     * the group did, and the group's undo is not theirs to cancel.
     */
    fun enqueue(entry: OpdsEntry, acquisition: OpdsAcquisition, sourceId: UUID, queue: DownloadQueue): String? {
        val id = queue.downloadId(entry.id, sourceId)
        if (queue.library.value[id] != null) return null
        queue.enqueue(entry, acquisition, sourceId = sourceId)
        return id
    }
}
