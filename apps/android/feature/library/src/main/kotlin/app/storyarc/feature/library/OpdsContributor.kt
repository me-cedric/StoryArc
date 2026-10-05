package app.storyarc.feature.library

import app.storyarc.core.catalogue.CatalogueAcquisition
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.util.UUID

/**
 * What an OPDS catalogue puts in the library.
 *
 * `library-browsing` requires one library over every source. A catalogue was reachable only
 * by browsing to it, which made it a place a reader travels to rather than part of their
 * library -- the thing `SourceKind.hasItsOwnBrowser` used to be for and no longer decides.
 *
 * **One feed, not a walk.** A catalogue is a tree of feeds and this reads the one the
 * reader saved, which is the root they chose. What is deeper stays reachable through the
 * browser and through search, which is what *More from a source than the library holds*
 * already requires. A crawl of every sub-feed would be unbounded, and a catalogue is
 * allowed to be a thousand pages deep.
 *
 * **No acquisition URL is kept.** An OPDS acquisition link can carry a key in its query,
 * and `sources` forbids a cached catalogue holding a credential. The row keeps the entry's
 * id and nothing else that reaches disk; how a row is opened is settled where the address
 * is still in hand.
 */
internal object OpdsContributor {

    /**
     * One feed page's entries as publications, and the feed's own `next` link.
     *
     * `sources`' *More from a source than the library holds*: the first read asks for
     * [page]'s own url; `LibraryViewModel.continueReadingCatalogues` asks every page after
     * it for [url] in turn, each time the [next] this same function returned for the page
     * before it -- a catalogue is a chain the server hands forward one link at a time, and
     * there is no offset or page number to ask for instead.
     */
    data class Page(val slice: SourceSlice, val next: String?)

    suspend fun page(sourceId: UUID, page: CataloguePage, pins: CertificatePins, url: String): Page {
        val feed = client(page, pins).feed(url, page.credential)
        val publications = feed.publications.mapNotNull { entry -> publication(sourceId, entry) }
        // The feed says so itself. A `next` link is the catalogue's own statement that this
        // page is not the whole of it, which is a better answer than counting entries
        // against a limit this side invented.
        return Page(SourceSlice(publications, holdsMore = feed.next != null), next = feed.next)
    }

    /**
     * The client the library read fetches with.
     *
     * 11.3: pulled out so a test can assert which `pins` reach it without a live catalogue.
     * Built with no pins before, which silently failed every catalogue behind a certificate
     * the reader had already pinned -- the client refused the handshake and [page]'s caller
     * saw an empty slice, never an error.
     */
    internal fun client(page: CataloguePage, pins: CertificatePins): OpdsClient =
        OpdsClient(pins = pins, origin = page.origin)

    /**
     * One entry as a row, or null for an entry that is not a publication.
     *
     * A feed's entries are not all books: a navigation entry is a way further in and has no
     * acquisition at all. Those belong to the browser, not to the library.
     *
     * **The acquisition kind decides, not a substring match on the media type.** An entry
     * whose only link is a loan or a subscription has nothing this app can fetch, and filing
     * it as a row anyway -- 11.5 -- offered a download that failed the moment it was tapped.
     * [CatalogueAcquisition.readable] already answers "what can the app act on", best format
     * first; this asks it rather than re-deriving the answer here.
     */
    internal fun publication(sourceId: UUID, entry: OpdsEntry): Publication? {
        val acquisition = CatalogueAcquisition.readable(entry).firstOrNull() ?: return null
        val format = PublicationFormat.ofMediaType(acquisition.mediaType) ?: return null
        return Publication(
            identity = PublicationIdentity(
                serverIdentifier = PublicationIdentity.ServerIdentifier(
                    sourceId = sourceId,
                    remoteId = "opds:${entry.id}",
                ),
            ),
            format = format,
            displayTitle = entry.title,
            series = entry.series,
            number = entry.seriesIndex?.let { index ->
                // A whole number reads as an issue and a fraction as a part of one, which is
                // how `Publication.number` is already spelled everywhere else.
                if (index % 1.0 == 0.0) index.toInt().toString() else index.toString()
            },
            authors = entry.authors,
            summary = entry.summary,
            origin = MetadataOrigin.AUTHORITATIVE,
            sourceId = sourceId,
            // What the feed says it weighs, which for a row with no file on the device is the
            // only size there is -- `offline-downloads` 6.4. A group of catalogue-only members
            // was confirmed as weighing nothing and then fetched hundreds of megabytes. Null
            // where the feed states no length, which is shown as unknown rather than as zero.
            fileSize = acquisition.length,
        )
    }
}
