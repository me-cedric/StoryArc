package app.storyarc.core.persistence

import android.content.Context
import java.io.File

/**
 * What StoryArc is using on disk, and how to give it back.
 *
 * `settings-and-about` asks for cache, reading history and downloads to be "individually
 * clearable, each stating what it removes and how much space it frees". A number is the
 * point: "clear cache" with no size behind it asks a reader to guess whether it is worth
 * doing.
 *
 * Downloads are not measured here. They are, but by whoever owns them: `DownloadStore`
 * walks its own directory and the size is handed to the Privacy screen, because this type
 * knows about the cache and the history and has no business knowing where a download lands.
 */
class StorageUsage(private val context: Context) {

    /** Bytes the cache directory is holding. Includes the web view's own. */
    fun cacheBytes(): Long = context.cacheDir.sizeOnDisk() + (context.externalCacheDir?.sizeOnDisk() ?: 0)

    /** Bytes the reading-position database is holding, journals included. */
    fun historyBytes(): Long =
        File(context.getDatabasePath("progress.db").parent ?: return 0)
            .listFiles { file -> file.name.startsWith("progress.db") }
            ?.sumOf { it.length() }
            ?: 0

    /**
     * Empties the cache.
     *
     * Contents rather than the directory itself: deleting the directory out from under a
     * web view that has it open is how the next page load finds nothing where it expected a
     * writable path.
     */
    fun clearCache() {
        context.cacheDir.listFiles()?.forEach { it.deleteRecursively() }
        context.externalCacheDir?.listFiles()?.forEach { it.deleteRecursively() }
    }

    private fun File.sizeOnDisk(): Long =
        walkBottomUp().filter { it.isFile }.sumOf { it.length() }
}
