package app.storyarc.core.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.math.floor

/**
 * The book being read, as the home-screen widget shows it.
 *
 * ADR-0011, prerequisite 1. The widget draws while the app may not be running, so it reads
 * this small record and nothing else: no Room database, no cover cache. The app writes the
 * record whenever the book it would offer to continue changes.
 *
 * The same fact [QuickActions.offered] names in the launcher menu, with the series and the
 * part read added. iOS's `ReadingSnapshot` mirrors it case for case.
 */
@ConsistentCopyVisibility
data class ReadingSnapshot internal constructor(
    val publicationId: String,
    val title: String,
    val series: String?,
    /** The whole percent read, from 0 to 100. Null for a publication with no position. */
    val percentRead: Int?,
) {

    /** The part read, from 0 to 1, for a progress bar. */
    val fractionRead: Float? get() = percentRead?.let { it / 100f }

    /**
     * The file name of this publication's cover, in the snapshot's folder.
     *
     * Named from the publication, so a cover can never be shown under another book's title.
     */
    val coverFile: String get() = coverFile(publicationId)

    /** The stored form. */
    fun encoded(): String = json.encodeToString(
        Stored.serializer(),
        Stored(VERSION, publicationId, title, series, percentRead),
    )

    companion object {
        /** The format of the stored record. A record in any other format is not read. */
        const val VERSION = 1

        /** The longest side of the stored cover, in pixels. */
        const val COVER_PIXELS = 480

        private val json = Json { ignoreUnknownKeys = true }

        /**
         * The snapshot of the book to continue, or null when there is none.
         *
         * A publication with no usable title gives no snapshot, for the reason [QuickActions]
         * gives. The percent is rounded down, so only a finished book shows 100, and a page
         * turn that does not move the whole percent writes nothing.
         */
        fun of(publication: Publication?, fractionRead: Double?): ReadingSnapshot? {
            val title = publication?.displayTitle?.trim()
            if (publication == null || title.isNullOrEmpty()) return null
            return make(publication.id, title, publication.series, fractionRead?.let { floor(it * 100).toInt() })
        }

        /**
         * Reads a stored record back. Null for a record that is malformed, in another format,
         * or that names no publication or no title.
         */
        fun decoded(text: String): ReadingSnapshot? {
            val stored = runCatching { json.decodeFromString(Stored.serializer(), text) }.getOrNull()
                ?: return null
            if (stored.version != VERSION || stored.publicationID.isEmpty() || stored.title.isBlank()) return null
            return make(stored.publicationID, stored.title, stored.series, stored.percentRead)
        }

        internal fun make(id: String, title: String, series: String?, percent: Int?) = ReadingSnapshot(
            publicationId = id,
            title = title,
            series = series?.trim()?.takeIf { it.isNotEmpty() },
            percentRead = percent?.coerceIn(0, 100),
        )

        /**
         * The cover file name for a publication identifier.
         *
         * An identifier holds a path, so it cannot be a file name. FNV-1a over its UTF-8 bytes
         * gives a short stable name, and iOS computes the same name for the same identifier.
         */
        fun coverFile(publicationId: String): String {
            var hash = -0x340d631b7bdddcdbL
            for (byte in publicationId.encodeToByteArray()) {
                hash = (hash xor (byte.toLong() and 0xFF)) * 0x100000001b3L
            }
            return "cover-" + hash.toULong().toString(16).padStart(16, '0') + ".jpg"
        }
    }

    /** The keys iOS writes, so the two stored forms read the same. */
    @Serializable
    private data class Stored(
        val version: Int,
        val publicationID: String,
        val title: String,
        val series: String? = null,
        val percentRead: Int? = null,
    )
}
