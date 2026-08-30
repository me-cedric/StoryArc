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
        val fetched = client.chapter(chapter.id)
        // Indexed where it lands first, because the download's own path is named after the
        // publication's identity and the identity comes out of the file.
        val staged = withContext(Dispatchers.IO) {
            kavitaCacheFile(context, chapter.id, fetched.mediaType).apply { writeBytes(fetched.bytes) }
        }
        val indexed = PublicationIndexer.index(staged, catalogueSeries = series.name)
        val mediaType = fetched.mediaType ?: indexed.format.mediaType ?: return@runCatching null
        // `library-browsing` attributes a download to the source its record names, which is
        // what puts a kept chapter on the one shelf that spans every source.
        val publication = indexed.copy(sourceId = sourceId)

        val destination = downloads.location(publication.id, mediaType, publication.displayTitle)
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

        downloads.save(
            downloads.library().queueing(
                Download(
                    id = publication.id,
                    sourceId = sourceId,
                    title = publication.displayTitle,
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

        cards.save(card(publication.id, chapter, series, metadata, origin))
        // The same note the open path leaves, and for the same reason: the reader opens a file
        // and knows nothing about servers, so this is what lets the position get home.
        progress.remember(publication.id, origin)

        Kept(publication, destination.absolutePath)
    }.getOrNull()

    /** What the server said, in the shape that survives it going away. */
    private fun card(
        publicationId: String,
        chapter: KavitaChapter,
        series: KavitaSeries,
        metadata: KavitaMetadata?,
        origin: KavitaOrigin,
    ) = KavitaCard(
        publicationId = publicationId,
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
    )
}
