package app.storyarc.feature.library

import android.content.Context
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaMetadata
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.model.KavitaCard
import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.KavitaCardStore
import app.storyarc.core.persistence.KavitaOrigin
import app.storyarc.core.persistence.KavitaProgressStore
import java.util.UUID

/**
 * Keeping a Kavita chapter on the device, as a download rather than as a cache file.
 *
 * **This is what "a downloaded Kavita publication" was missing.** `kavita-server` has a
 * scenario about opening one "with the server unreachable", and the subject of that sentence
 * did not exist: every chapter the browser fetched went to the cache directory, which nothing
 * lists, nothing attributes to a source, nothing counts in Settings > Downloads and storage,
 * and the system may reclaim between two launches. The comment that sent it there was right
 * about the distinction -- "a chapter opened once is not a download the reader asked to keep"
 * -- and wrong that there was no way to ask.
 *
 * So opening still writes a cache file, and *keeping* writes a download: the same
 * [DownloadStore] every other kept publication goes through, with the same record, the same
 * per-source attribution, the same removal, and the same hardened naming. That store was
 * hardened this session against an id made of dots; a second path that wrote files beside it
 * would be a second path to harden.
 *
 * The card goes with it. A download whose metadata is fetched on arrival is a download that
 * has no metadata when the server is away, which is the scenario.
 *
 * iOS's `KavitaKeep` does the same four steps in the same order.
 */
object KavitaKeep {
    /** What a keep produced, for the caller that wants to open it straight away. */
    data class Kept(val publication: Publication, val path: String)

    /**
     * Queues a chapter, waits for its file, and writes down what the server said.
     *
     * Null when any step fails, and deliberately without a half-kept result: a record whose
     * bytes are not there reads to a reader as a library that lost their book, which is the
     * failure [DownloadStore] exists to make impossible.
     *
     * **The transfer is the queue's, not this object's.** `offline-downloads` 1.9: the body
     * used to be read whole into memory, written to a cache file and moved into the store by
     * hand, so a kept chapter had no row in the downloads view and none of the pause, resume or
     * retry *Queue management* promises -- and a collected edition was an array the size of
     * itself. [fetchChapter] streams it to disk instead, and the token travels with the chapter
     * because the secure store holds the API key that mints one rather than the token this
     * route needs.
     *
     * The three steps afterwards are unchanged: index the landed file, file the card, and
     * remember where the chapter sits on the server.
     */
    suspend fun keep(
        context: Context,
        chapter: KavitaChapter,
        series: KavitaSeries,
        metadata: KavitaMetadata?,
        origin: KavitaOrigin,
        sourceId: UUID?,
        client: KavitaClient,
        /** The app-level queue, which is the only writer of the download store -- dl-core 1.1. */
        queue: DownloadQueue,
        cards: KavitaCardStore = KavitaCardStore.open(context),
        progress: KavitaProgressStore = KavitaProgressStore.open(context),
    ): Kept? = runCatching {
        val title = KavitaNaming.title(series, chapter)

        // The record's own identifier, and therefore the directory the bytes go in.
        //
        // The server's chapter, not the file's identity. It was the file's, and driving it
        // showed why that cannot work: the identity of a publication is its path, the path is
        // chosen from the identity, and the file the reader ends up with is at a *third* path
        // -- so the card was filed under the staging directory and the shelf, indexing the
        // download, never found it. A catalogue download has the same shape and solved it the
        // same way: `Download.id` is what the *source* calls the thing.
        val identifier = "kavita:${origin.sourceId}:${chapter.id}"
        val destination = queue.fetchChapter(
            id = identifier,
            title = title,
            // No secret in it: Kavita takes the key as a bearer header on this route, not in
            // the query, so what is written down is a path and a chapter number.
            remote = client.address.chapterUrl(chapter.id),
            sourceId = sourceId,
            credential = OpdsCredential.Bearer(client.authorization()),
            seriesHint = series.name,
        ) ?: return@runCatching null

        // Indexed where it landed, which is the identity the library will compute when it walks
        // the download tree -- and what the card has to be filed under for the server's metadata
        // to reach the shelf. `library-browsing` attributes a download to the source its record
        // names, which is what puts a kept chapter on the one shelf that spans every source.
        val publication = PublicationIndexer.index(destination, catalogueSeries = series.name)
            .copy(sourceId = sourceId)

        cards.save(card(publication.id, identifier, chapter, series, metadata, origin))
        // The same note the open path leaves, and for the same reason: the reader opens a file
        // and knows nothing about servers, so this is what lets the position get home.
        progress.remember(publication.id, origin)

        Kept(publication, destination.absolutePath)
    }.getOrNull()

    /**
     * What the server said, in the shape that survives it going away.
     *
     * **All seven of `kavita-server`'s metadata fields** -- "summary, genres, tags, people,
     * publication status, age rating, and release year". The last two were the gap: the
     * series screen showed them from the live answer and [KavitaCard] had no field for
     * either, so *Reading a downloaded Kavita title offline* fell back to the file's
     * `ComicInfo.xml` for exactly those two while preferring the server's word for the rest.
     *
     * The two defaults are not the same shape, and that is deliberate. A rating the server
     * did not state is Kavita's own `Unknown`, which is zero and draws no line. A *status* it
     * did not state has no number of its own -- zero is `OnGoing`, a real state -- so the
     * card carries -1, outside Kavita's table, rather than telling a reader a series is
     * running on a server's behalf.
     *
     * Both absences reach the -1, and that is why [KavitaMetadata.publicationStatus] is
     * nullable: the server not answering at all, and the server answering without the field.
     * The second is the ordinary one -- Kavita omits what a series does not have -- and a
     * non-nullable field defaulted to zero would have turned it into *OnGoing* here.
     *
     * Internal rather than private because these two lines are the whole feature: hardcode
     * them to the two absences and every screen in the app still composes.
     * `KavitaKeepCardTest` is the test that fails.
     */
    internal fun card(
        publicationId: String,
        downloadId: String,
        chapter: KavitaChapter,
        series: KavitaSeries,
        metadata: KavitaMetadata?,
        origin: KavitaOrigin,
    ) = KavitaCard(
        publicationId = publicationId,
        downloadId = downloadId,
        sourceId = origin.sourceId,
        libraryId = origin.libraryId,
        seriesId = series.id,
        chapterId = chapter.id,
        seriesName = series.name,
        // The same name the shelf gives it. `chapter.displayName` is the raw one, empty
        // for an unnumbered chapter, and the card's name is written straight over
        // `Publication.displayTitle` when the download is adopted -- so an empty one here
        // is a shelf row with no title, and the sentinel was worse.
        chapterName = KavitaNaming.title(series, chapter),
        summary = metadata?.summary,
        people = metadata?.people.orEmpty(),
        subjects = metadata?.subjects.orEmpty(),
        releaseYear = metadata?.releaseYear ?: 0,
        ageRating = metadata?.ageRating ?: 0,
        publicationStatus = metadata?.publicationStatus ?: -1,
    )
}
