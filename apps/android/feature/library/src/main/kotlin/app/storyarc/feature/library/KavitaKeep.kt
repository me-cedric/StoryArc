package app.storyarc.feature.library

import android.content.Context
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaMetadata
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.model.Download
import app.storyarc.core.model.KavitaCard
import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.KavitaCardStore
import app.storyarc.core.persistence.KavitaOrigin
import app.storyarc.core.persistence.KavitaProgressStore
import java.util.Date
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

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
     * Fetches a chapter, files it as a download, and writes down what the server said.
     *
     * Null when any step fails, and deliberately without a half-kept result: a record whose
     * bytes are not there reads to a reader as a library that lost their book, which is the
     * failure [DownloadStore] exists to make impossible.
     */
    suspend fun keep(
        context: Context,
        chapter: KavitaChapter,
        series: KavitaSeries,
        metadata: KavitaMetadata?,
        origin: KavitaOrigin,
        sourceId: UUID?,
        client: KavitaClient,
        downloads: DownloadStore = DownloadStore.open(context),
        cards: KavitaCardStore = KavitaCardStore.open(context),
        progress: KavitaProgressStore = KavitaProgressStore.open(context),
    ): Kept? = runCatching {
        val title = chapter.displayName.ifEmpty { "${series.name} ${chapter.number}" }
        val fetched = client.chapter(chapter.id)
        val staged = withContext(Dispatchers.IO) {
            kavitaCacheFile(context, chapter.id, fetched.mediaType).apply { writeBytes(fetched.bytes) }
        }
        // The server's word is preferred and is usually there. Indexing the staged copy is the
        // fallback for a server that sent no type, because the extension the download is
        // written under decides which reader opens it.
        val mediaType = fetched.mediaType
            ?: PublicationIndexer.index(staged).format.mediaType
            ?: return@runCatching null

        // The record's own identifier, and therefore the directory the bytes go in.
        //
        // The server's chapter, not the file's identity. It was the file's, and driving it
        // showed why that cannot work: the identity of a publication is its path, the path is
        // chosen from the identity, and the file the reader ends up with is at a *third* path
        // -- so the card was filed under the staging directory and the shelf, indexing the
        // download, never found it. A catalogue download has the same shape and solved it the
        // same way: `Download.id` is what the *source* calls the thing.
        val identifier = "kavita:${origin.sourceId}:${chapter.id}"
        val destination = downloads.location(identifier, mediaType, title)
        val bytes = withContext(Dispatchers.IO) {
            downloads.prepare()
            downloads.prepare(destination)
            // Replaced rather than refused, for the reason `KeepForOffline` gives: a file left
            // by a removal that only got half way is not a reason to refuse the reader their
            // comic.
            destination.delete()
            if (!staged.renameTo(destination)) {
                staged.copyTo(destination, overwrite = true)
                staged.delete()
            }
            destination.length()
        }

        // Indexed where it landed, not where it was staged. This is the identity the library
        // will compute when it walks the download tree, which is what the card has to be filed
        // under for the server's metadata to reach the shelf.
        // `library-browsing` attributes a download to the source its record names, which is
        // what puts a kept chapter on the one shelf that spans every source.
        val publication = PublicationIndexer.index(destination, catalogueSeries = series.name)
            .copy(sourceId = sourceId)

        downloads.save(
            downloads.library().queueing(
                Download(
                    id = identifier,
                    sourceId = sourceId,
                    title = title,
                    // No secret in it: Kavita takes the key as a bearer header on this route,
                    // not in the query, so what is written down is a path and a chapter number.
                    remote = client.address.chapterUrl(chapter.id),
                    mediaType = mediaType,
                    state = Download.State.Finished,
                    expectedBytes = bytes,
                    downloadedBytes = bytes,
                    completedAt = Date(),
                ),
            ),
        )

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
        chapterName = chapter.displayName,
        summary = metadata?.summary,
        people = metadata?.people.orEmpty(),
        subjects = metadata?.subjects.orEmpty(),
        releaseYear = metadata?.releaseYear ?: 0,
        ageRating = metadata?.ageRating ?: 0,
        publicationStatus = metadata?.publicationStatus ?: -1,
    )
}
