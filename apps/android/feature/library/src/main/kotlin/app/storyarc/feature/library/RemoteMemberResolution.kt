package app.storyarc.feature.library

import app.storyarc.core.catalogue.CatalogueAcquisition
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsFeed

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
}
