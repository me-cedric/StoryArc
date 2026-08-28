package app.storyarc.core.model

import java.util.Date
import java.util.UUID

/**
 * A publication taken from a remote source and kept on the device.
 *
 * `offline-downloads` is about "taking a library with you", and the first thing that
 * requires is a record: what was fetched, from where, how big it is, and whether it is
 * finished. Without one, a fetched file is a file in a cache directory that nothing can
 * list, attribute, or remove -- which is exactly what the catalogue's first cut produced.
 *
 * iOS's `Download` is the same record.
 */
data class Download(
    /**
     * The publication's stable identity, so a download and a library row are the same thing
     * seen twice rather than two rows that happen to share a title.
     */
    val id: String,
    /**
     * Which source it came from, for the storage view's per-source breakdown and so removing
     * a source can take its downloads with it.
     */
    val sourceId: UUID? = null,
    val title: String,
    /** Where it came from, so a failed download can be retried without re-browsing. */
    val remote: String,
    val mediaType: String,
    val state: State = State.Queued,
    /**
     * What the server said the whole thing weighs, when it said. Null when it did not:
     * `offline-downloads` requires a size to be *shown*, and a fabricated one is worse than
     * an honest blank.
     */
    val expectedBytes: Long? = null,
    /** What is on disk now. */
    val downloadedBytes: Long = 0,
    val completedAt: Date? = null,
) {
    /** Where a download is in its life. */
    sealed interface State {
        data object Queued : State
        data object Running : State
        data class Paused(val reason: Pause) : State

        /**
         * Retried and still failing. `offline-downloads`: after three attempts a download is
         * "marked failed with a plain-language reason and a retry action", so both the
         * reason and the count are part of the state rather than logged and forgotten.
         */
        data class Failed(val reason: String, val attempts: Int) : State

        data object Finished : State

        /** Whether the file on disk is complete and verified. */
        val isFinished: Boolean get() = this == Finished

        /** Whether the app should be moving bytes for this one. */
        val isActive: Boolean get() = this == Running || this == Queued
    }

    /** Why a download is not running, in the reader's terms rather than the system's. */
    enum class Pause {
        /** The reader asked. */
        BY_READER,

        /**
         * `offline-downloads`: on a metered connection with Wi-Fi-only on, downloads "pause
         * and state that they are waiting for Wi-Fi".
         */
        WAITING_FOR_WIFI,

        /**
         * The device is out of room. Never resolved by deleting something silently: the spec
         * says the app "never deletes a download without asking".
         */
        OUT_OF_SPACE,
    }

    /**
     * How far along, when the size is known.
     *
     * Null rather than zero for an unknown size, so a progress bar can show an indeterminate
     * state instead of a bar that never moves.
     */
    val fraction: Double?
        get() {
            val expected = expectedBytes ?: return null
            if (expected <= 0) return null
            return minOf(1.0, downloadedBytes.toDouble() / expected.toDouble())
        }
}

/**
 * Every download the app knows about, and every change that can be made to the set.
 *
 * A value type with pure operations, like [SourceRegistry]. The queue's *order* is the
 * reader's -- `offline-downloads` asks for "per-item and global pause, resume, cancel, and
 * reorder" -- so this is a list, not a map keyed by identity.
 */
data class DownloadLibrary(val downloads: List<Download> = emptyList()) {

    operator fun get(id: String): Download? = downloads.firstOrNull { it.id == id }

    /** The ones still to do, in the order they will be done. */
    val pending: List<Download> get() = downloads.filterNot { it.state.isFinished }

    /** The ones on disk. */
    val finished: List<Download> get() = downloads.filter { it.state.isFinished }

    /** What all the finished downloads weigh, for the storage view. */
    val bytesOnDisk: Long get() = finished.sumOf { it.downloadedBytes }

    /**
     * Queues a download, or does nothing if this publication is already known.
     *
     * `offline-downloads`: when a publication is already downloaded "the app does not
     * re-fetch it". Enforced here rather than at the call site, because there are three call
     * sites and only one of them would remember.
     */
    fun queueing(download: Download): DownloadLibrary =
        if (this[download.id] != null) this else copy(downloads = downloads + download)

    /** Records a change of state. */
    fun marking(id: String, state: Download.State): DownloadLibrary = copy(
        downloads = downloads.map {
            if (it.id != id) {
                it
            } else {
                it.copy(
                    state = state,
                    completedAt = if (state == Download.State.Finished) Date() else it.completedAt,
                )
            }
        },
    )

    /** Records progress, and the total once the server has stated it. */
    fun advancing(id: String, downloaded: Long, expected: Long? = null): DownloadLibrary = copy(
        downloads = downloads.map {
            if (it.id != id) {
                it
            } else {
                it.copy(downloadedBytes = downloaded, expectedBytes = expected ?: it.expectedBytes)
            }
        },
    )

    /**
     * Moves a download in the queue.
     *
     * Takes the destination a drag reports, which is an index in the list *before* the move
     * -- the same convention [SourceRegistry.moving] uses, and for the same reason: removing
     * first and inserting after lands one place early on every downward drag.
     */
    fun moving(id: String, destination: Int): DownloadLibrary {
        val from = downloads.indexOfFirst { it.id == id }
        if (from < 0) return this
        val moved = downloads.toMutableList()
        val download = moved.removeAt(from)
        val to = (if (destination > from) destination - 1 else destination)
            .coerceIn(0, moved.size)
        moved.add(to, download)
        return copy(downloads = moved)
    }

    /** Forgets a download. The file is the caller's to delete. */
    fun removing(id: String): DownloadLibrary = copy(downloads = downloads.filterNot { it.id == id })

    /** Forgets everything a source contributed, for when the source itself is removed. */
    fun removingAll(sourceId: UUID): Pair<DownloadLibrary, List<Download>> {
        val removed = downloads.filter { it.sourceId == sourceId }
        return copy(downloads = downloads.filterNot { it.sourceId == sourceId }) to removed
    }

    /**
     * Records a failed attempt, counting it.
     *
     * Always leaves the download failed. Whether to try again is [shouldRetry]'s question,
     * asked by the queue -- a state that re-queued itself would make "failed" mean two
     * different things and leave nothing for the reader to see between attempts.
     */
    fun failing(id: String, reason: String): DownloadLibrary = copy(
        downloads = downloads.map {
            if (it.id != id) {
                it
            } else {
                val previous = (it.state as? Download.State.Failed)?.attempts ?: 0
                it.copy(state = Download.State.Failed(reason, previous + 1))
            }
        },
    )

    companion object {
        /** Three, from `offline-downloads`. */
        const val ATTEMPT_LIMIT = 3

        /** Whether a failed download has attempts left. */
        fun shouldRetry(download: Download): Boolean {
            val failed = download.state as? Download.State.Failed ?: return false
            return failed.attempts < ATTEMPT_LIMIT
        }

        /**
         * How long to wait before the next attempt, in milliseconds.
         *
         * Doubling from two seconds, which is the "backoff" the spec asks for. Short,
         * because the common failure is a server that was briefly busy or a phone that
         * changed network, not one that will be down for an hour.
         */
        fun backoffMillis(attempts: Int): Long = 2000L shl maxOf(0, attempts - 1)
    }
}
