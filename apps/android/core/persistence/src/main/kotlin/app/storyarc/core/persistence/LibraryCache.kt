package app.storyarc.core.persistence

import app.storyarc.core.model.Publication
import java.io.File
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * The library as it was last seen, so opening the app does not mean walking every folder
 * before anything appears.
 *
 * `sources`: the catalogue is cached "so the library opens instantly and stays browsable
 * while offline", and a refresh "updates the view incrementally rather than clearing it and
 * re-populating". This is the first half. The second is the scan, which appends to what
 * this restored and removes only what it can prove is gone.
 *
 * In the cache directory, deliberately. Losing this costs a rescan and nothing else — no
 * reading position, no download, no source — so it is exactly the kind of thing Android
 * should be free to reclaim, and the kind of thing the Privacy screen's "Clear cache"
 * should take with it. Covers live beside it for the same reason.
 *
 * One file rather than a row per publication. The whole library is read at once to draw one
 * screen, and a store that read it a row at a time would let two halves of the same
 * snapshot disagree — the same argument [SourceStore] makes for the registry.
 *
 * iOS's `LibraryCache` writes the same shape.
 */
class LibraryCache(private val file: File) {

    /** What was on the shelf, and when it was last confirmed. */
    @Serializable
    data class Snapshot(
        /** When a scan last completed. What the "cached, last refreshed…" indicator states. */
        val refreshedAtEpochMillis: Long,
        val publications: List<Publication> = emptyList(),
        /**
         * Where each publication was, keyed by its stable id.
         *
         * Strings rather than resolved trees: this is a cache, and a location that no longer
         * resolves is a publication the next scan will not find and will remove.
         */
        val locations: Map<String, String> = emptyMap(),
    )

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    /**
     * The last snapshot, or null when there is none this build can read.
     *
     * A snapshot written by a newer version is discarded rather than guessed at. It costs
     * one rescan, which is what a cache miss is supposed to cost.
     */
    fun read(): Snapshot? {
        if (!file.isFile) return null
        return runCatching { json.decodeFromString<Snapshot>(file.readText()) }.getOrNull()
    }

    /**
     * Writes the snapshot, replacing whatever was there.
     *
     * Failure is silent and correct: this is a cache. A device with no room left should show
     * the library, not refuse to.
     */
    fun write(snapshot: Snapshot) {
        runCatching {
            file.parentFile?.mkdirs()
            file.writeText(json.encodeToString(snapshot))
        }
    }

    /** Forgets the shelf. The Privacy screen's "Clear cache", and the tests. */
    fun clear() {
        runCatching { file.delete() }
    }
}
