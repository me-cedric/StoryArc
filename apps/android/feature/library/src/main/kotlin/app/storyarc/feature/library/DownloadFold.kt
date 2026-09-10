package app.storyarc.feature.library

import app.storyarc.core.model.KavitaCard
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationIdentity

/**
 * How a downloaded file joins the row the source it came from already put on the shelf.
 *
 * `library-browsing`: a publication a source offers and the same publication downloaded are
 * one row. They were two. A server row is identified by its `ServerIdentifier` and nothing
 * else -- there is no file yet -- and a downloaded file is identified by its path and its
 * digest, so `PublicationIdentity.matches` had nothing in common to match on. The library
 * drew the download beside the row it was downloaded from, and the reader saw a duplicate
 * the moment a Kavita chapter finished.
 *
 * **The card is the bridge.** It is written when the chapter is kept and holds the source
 * and the chapter, which is exactly the pair `KavitaContributor` builds a server identifier
 * from. Recording it on the downloaded file's identity is all the fold is:
 * `PublicationIdentity.matches` then finds the remote row, and `stableId` keeps preferring
 * the path — which is why the *existing* row's identity is the one kept, so nothing filed
 * against the remote row's key moves when the bytes arrive.
 *
 * Pure and generic over the row, so the decision can be asserted without a library, a
 * download store or an archive on disk. `DownloadFoldTest` is that assertion; iOS's
 * `DownloadFold` is the twin.
 */
internal object DownloadFold {

    /**
     * The downloaded publication as the shelf should hold it: described by the card, and
     * carrying the identifier of the row it is a copy of.
     *
     * `kavita-server` requires the server's description to win over the file's own, which
     * is what [KavitaCard.appliedTo] does; the identifier is what makes the two one row.
     * A card the store does not hold changes neither: a file downloaded from an OPDS
     * catalogue, or imported by hand, has no server row to join and no cached description.
     */
    fun described(publication: Publication, card: KavitaCard?): Publication {
        val described = card?.appliedTo(publication) ?: publication
        val server = card?.remoteIdentity ?: return described
        return described.copy(identity = described.identity.recordingServer(server))
    }

    /**
     * Which row on the shelf this file belongs to, or null when it is a new one.
     *
     * The first match, because two rows that both match would already be one row.
     */
    fun rowFor(rows: List<Publication>, downloaded: Publication): Int? =
        rows.indexOfFirst { it.identity.matches(downloaded.identity) }.takeIf { it >= 0 }
}
