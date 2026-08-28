package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import java.io.File
import java.util.Date
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * What has been downloaded, on disk and in a list.
 *
 * Two halves that have to agree: the files, and the record of them. This owns both, so there
 * is one place where "the app thinks it has this" and "the bytes are there" can be made true
 * together -- the alternative is a list that outlives its files, which reads to a reader as
 * a library that lost their book.
 *
 * The directory is `files/downloads`, which `backup_rules.xml` and `data_extraction_rules
 * .xml` already exclude from backup. `offline-downloads` requires that: downloads are
 * re-downloadable and would otherwise dominate a backup. iOS sets the same exclusion as a
 * resource value on its own directory.
 */
class DownloadStore internal constructor(
    private val preferences: SharedPreferences,
    /** Where the files live. */
    val directory: File,
) {
    companion object {
        private const val NAME = "app.storyarc.downloads"
        private const val KEY = "library"

        fun open(context: Context): DownloadStore = DownloadStore(
            context.getSharedPreferences(NAME, Context.MODE_PRIVATE),
            File(context.filesDir, "downloads"),
        )

        private val json = Json { ignoreUnknownKeys = true }
    }

    fun library(): DownloadLibrary {
        val stored = preferences.getString(KEY, null) ?: return DownloadLibrary()
        return runCatching {
            DownloadLibrary(json.decodeFromString<List<StoredDownload>>(stored).map { it.download() })
        }.getOrDefault(DownloadLibrary())
    }

    fun save(library: DownloadLibrary) {
        val stored = json.encodeToString(library.downloads.map(::StoredDownload))
        preferences.edit().putString(KEY, stored).apply()
    }

    /**
     * Where one publication's file goes.
     *
     * Named by identity rather than title: two catalogues can offer the same title, and a
     * filename collision would hand the reader the wrong book.
     */
    /**
     * Where one download's file lives.
     *
     * The id is the directory and [named] is the file's own name. It used to be the other
     * way round, and an OPDS download landed as `urn-storyarc-6.cbz`: the indexer reads a
     * title and a series out of a filename, so a downloaded comic was called after its
     * identifier everywhere, and `comic-reader`'s per-series settings keyed on one issue.
     * The id still makes the path unique; it no longer has to be the name as well.
     */
    fun location(id: String, extension: String, named: String? = null): File {
        val folder = File(directory, safe(id))
        val stem = named?.let(::safe)?.takeIf { it.isNotBlank() } ?: safe(id)
        return File(folder, "$stem.$extension")
    }

    /** A name a filesystem will take: no separators, nothing that reads as a path. */
    private fun safe(text: String): String = text.replace(Regex("[^A-Za-z0-9._ -]"), "-")

    /** Makes the directory. */
    fun prepare() {
        directory.mkdirs()
    }

    /** Makes the directory one download's file goes in. */
    fun prepare(file: File) {
        file.parentFile?.mkdirs()
    }

    /** Deletes one download's file, and returns whether there was one. */
    fun delete(file: File): Boolean = file.delete()

    /**
     * What the files actually weigh, which is not always what the record says.
     *
     * Asked of the disk rather than trusted from the list: a storage total that counts bytes
     * nobody has is the kind of number that makes a reader distrust the whole screen.
     */
    // Walked, not listed: each download sits in a directory of its own, so the top level
    // holds no files at all and a listing of it would total zero.
    fun bytesOnDisk(): Long = directory.walkTopDown().filter { it.isFile }.sumOf { it.length() }

    /** Forgets every download. Used by a reset, and by the tests. */
    fun reset() {
        preferences.edit().clear().apply()
        directory.deleteRecursively()
    }
}

/**
 * What is actually written.
 *
 * A separate shape rather than making [Download] serialisable, for the same reason the source
 * registry has one: the durable fields and the runtime ones are different sets. A download
 * that was *running* when the app died is queued when it comes back, because "running"
 * describes a transfer that is no longer happening.
 */
@Serializable
private data class StoredDownload(
    val id: String,
    val sourceId: String?,
    val title: String,
    val remote: String,
    val mediaType: String,
    val expectedBytes: Long?,
    val downloadedBytes: Long,
    val completedAt: Long?,
    val isFinished: Boolean,
    val failure: String?,
    val attempts: Int,
) {
    constructor(download: Download) : this(
        id = download.id,
        sourceId = download.sourceId?.toString(),
        title = download.title,
        remote = download.remote,
        mediaType = download.mediaType,
        expectedBytes = download.expectedBytes,
        downloadedBytes = download.downloadedBytes,
        completedAt = download.completedAt?.time,
        isFinished = download.state.isFinished,
        failure = (download.state as? Download.State.Failed)?.reason,
        attempts = (download.state as? Download.State.Failed)?.attempts ?: 0,
    )

    fun download(): Download = Download(
        id = id,
        sourceId = sourceId?.let { runCatching { UUID.fromString(it) }.getOrNull() },
        title = title,
        remote = remote,
        mediaType = mediaType,
        state = when {
            isFinished -> Download.State.Finished
            failure != null -> Download.State.Failed(failure, attempts)
            else -> Download.State.Queued
        },
        expectedBytes = expectedBytes,
        downloadedBytes = downloadedBytes,
        completedAt = completedAt?.let(::Date),
    )
}
