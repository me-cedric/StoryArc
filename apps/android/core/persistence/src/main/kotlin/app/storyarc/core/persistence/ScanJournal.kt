package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingDirection
import app.storyarc.core.model.StreamingCapability
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * What a scan has produced so far, kept so an interrupted one can pick up.
 *
 * `local-library` requires a folder scan to be "cancellable and resumable". Cancellable is
 * free -- the walk stops when its coroutine does. Resumable is not: a scan of ten thousand
 * comics is minutes of opening archives, and a reader who left the app or whose phone
 * reclaimed the process would otherwise watch the whole thing happen again.
 *
 * So the scan writes down what it has indexed, in batches, and the next scan of the same
 * folder puts those publications straight into the library and walks past the files they
 * came from. Nothing is opened twice.
 *
 * Deliberately **not** a metadata cache. The journal is cleared the moment a scan finishes,
 * because a completed scan has nothing left to resume -- `sources` asks for a cache that
 * survives a launch and keeps a library browsable offline, and that is a different
 * requirement with different rules about staleness. iOS's `ScanJournal` is the same store.
 */
class ScanJournal internal constructor(private val preferences: SharedPreferences) {

    companion object {
        private const val NAME = "app.storyarc.scan-journal"
        private const val KEY = "folders"

        fun open(context: Context): ScanJournal =
            ScanJournal(context.getSharedPreferences(NAME, Context.MODE_PRIVATE))

        private val json = Json { ignoreUnknownKeys = true }
    }

    /**
     * What a scan of this folder had already indexed when it stopped.
     *
     * Empty when the last scan finished, which is the usual case.
     */
    fun indexed(folder: String): List<Publication> =
        stored()[folder].orEmpty().map { it.publication() }

    /**
     * Records what a scan has produced so far.
     *
     * The whole list each time rather than an append: the writer holds it anyway, and a
     * store that could be half-written is exactly the thing a resume must not read.
     */
    fun record(publications: List<Publication>, folder: String) {
        save(stored() + (folder to publications.map(::StoredPublication)))
    }

    /** Forgets a folder's journal. Called when its scan finishes. */
    fun clear(folder: String) {
        val all = stored()
        if (folder !in all) return
        save(all - folder)
    }

    /** Forgets every journal. Used by a reset, and by the tests. */
    fun reset() {
        preferences.edit().clear().apply()
    }

    private fun stored(): Map<String, List<StoredPublication>> {
        val text = preferences.getString(KEY, null) ?: return emptyMap()
        return runCatching {
            json.decodeFromString<Map<String, List<StoredPublication>>>(text)
        }.getOrDefault(emptyMap())
    }

    private fun save(all: Map<String, List<StoredPublication>>) {
        preferences.edit().putString(KEY, json.encodeToString(all)).apply()
    }
}

/**
 * What is actually written.
 *
 * A flat shape rather than a serialisable [Publication], for the same reason `StoredDownload`
 * exists: what is durable is this store's decision, and an annotation on the domain type
 * would let any future field reach the disk without anyone deciding it should. It also keeps
 * the identity's [UUID] out of the serialiser's way.
 */
@Serializable
private data class StoredPublication(
    val serverSourceId: String? = null,
    val serverRemoteId: String? = null,
    val contentDigest: String? = null,
    val normalizedPath: String? = null,
    val format: String,
    val displayTitle: String,
    val series: String? = null,
    val number: String? = null,
    val volume: Int? = null,
    val authors: List<String> = emptyList(),
    val publisher: String? = null,
    val year: Int? = null,
    val language: String? = null,
    val summary: String? = null,
    val origin: String,
    val pageCount: Int? = null,
    val skippedPageCount: Int = 0,
    val coverPath: String? = null,
    val readingDirection: String,
    val isFixedLayout: Boolean = false,
    val streaming: String,
    val sourceId: String? = null,
) {
    constructor(publication: Publication) : this(
        serverSourceId = publication.identity.serverIdentifier?.sourceId?.toString(),
        serverRemoteId = publication.identity.serverIdentifier?.remoteId,
        contentDigest = publication.identity.contentDigest,
        normalizedPath = publication.identity.normalizedPath,
        format = publication.format.name,
        displayTitle = publication.displayTitle,
        series = publication.series,
        number = publication.number,
        volume = publication.volume,
        authors = publication.authors,
        publisher = publication.publisher,
        year = publication.year,
        language = publication.language,
        summary = publication.summary,
        origin = publication.origin.name,
        pageCount = publication.pageCount,
        skippedPageCount = publication.skippedPageCount,
        coverPath = publication.coverPath,
        readingDirection = publication.readingDirection.name,
        isFixedLayout = publication.isFixedLayout,
        streaming = publication.streaming.name,
        sourceId = publication.sourceId?.toString(),
    )

    /**
     * A row this build cannot read comes back with a sane default rather than being dropped,
     * so a resumed scan does not silently lose a file it had already done.
     */
    fun publication(): Publication = Publication(
        identity = PublicationIdentity(
            serverIdentifier = serverSourceId
                ?.let { runCatching { UUID.fromString(it) }.getOrNull() }
                ?.let { source ->
                    serverRemoteId?.let { PublicationIdentity.ServerIdentifier(source, it) }
                },
            contentDigest = contentDigest,
            normalizedPath = normalizedPath,
        ),
        format = runCatching { PublicationFormat.valueOf(format) }
            .getOrDefault(PublicationFormat.CBZ),
        displayTitle = displayTitle,
        series = series,
        number = number,
        volume = volume,
        authors = authors,
        publisher = publisher,
        year = year,
        language = language,
        summary = summary,
        origin = runCatching { MetadataOrigin.valueOf(origin) }
            .getOrDefault(MetadataOrigin.INFERRED),
        pageCount = pageCount,
        skippedPageCount = skippedPageCount,
        coverPath = coverPath,
        readingDirection = runCatching { ReadingDirection.valueOf(readingDirection) }
            .getOrDefault(ReadingDirection.LEFT_TO_RIGHT),
        isFixedLayout = isFixedLayout,
        streaming = runCatching { StreamingCapability.valueOf(streaming) }
            .getOrDefault(StreamingCapability.STREAMS),
        sourceId = sourceId?.let { runCatching { UUID.fromString(it) }.getOrNull() },
    )
}
