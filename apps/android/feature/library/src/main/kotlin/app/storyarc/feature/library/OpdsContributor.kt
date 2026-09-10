package app.storyarc.feature.library

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
 * library -- the thing `SourceKind.isBrowsable` used to be for and no longer decides.
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

    /** The entries of the feed a reader saved, as publications. */
    suspend fun publications(sourceId: UUID, page: CataloguePage): List<Publication> {
        val feed = OpdsClient(origin = page.origin).feed(page.url, page.credential)
        return feed.publications.mapNotNull { entry -> publication(sourceId, entry) }
    }

    /**
     * One entry as a row, or null for an entry that is not a publication.
     *
     * A feed's entries are not all books: a navigation entry is a way further in and has no
     * acquisition at all. Those belong to the browser, not to the library.
     */
    internal fun publication(sourceId: UUID, entry: OpdsEntry): Publication? {
        val format = entry.acquisitions.firstNotNullOfOrNull { format(it.mediaType) }
            ?: return null
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
        )
    }

    /**
     * The media type a feed declares, as a format this app can file under.
     *
     * Null for a type the app cannot open, which drops the entry rather than listing
     * something that refuses when tapped. `publication-formats` asks for a named refusal
     * where a reader meets one, and a library row is not that place -- the browser is,
     * where the reader chose the thing.
     */
    private fun format(mediaType: String?): PublicationFormat? = when {
        mediaType == null -> null
        // Named formats before container suffixes, because an EPUB *is* a zip and says so:
        // `application/epub+zip` matched the comic-archive branch and filed every book on
        // every catalogue as a comic. The test that caught it is the one worth keeping.
        mediaType.contains("epub") -> PublicationFormat.EPUB
        mediaType.contains("pdf") -> PublicationFormat.PDF
        mediaType.contains("cbz") || mediaType.contains("zip") -> PublicationFormat.CBZ
        mediaType.contains("cbr") || mediaType.contains("rar") -> PublicationFormat.CBR
        mediaType.contains("cb7") || mediaType.contains("7z") -> PublicationFormat.CB7
        mediaType.contains("cbt") || mediaType.contains("tar") -> PublicationFormat.CBT
        else -> null
    }
}
