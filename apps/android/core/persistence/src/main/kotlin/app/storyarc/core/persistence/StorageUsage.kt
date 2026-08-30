package app.storyarc.core.persistence

import android.content.Context
import android.webkit.CookieManager
import android.webkit.WebStorage
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
 *
 * The primary constructor takes the places rather than the [Context] that names them, so
 * that a unit test can drive [clearCache] against a temporary directory and a lambda it can
 * watch. `CookieManager` and `WebStorage` are platform singletons backed by a WebView a JVM
 * test has none of, which is the same reason iOS injects its `WKWebsiteDataStore` call.
 */
class StorageUsage internal constructor(
    private val cacheDirectories: List<File>,
    private val progressDatabase: File,
    private val removeWebViewData: () -> Unit,
) {
    constructor(context: Context) : this(
        cacheDirectories = listOfNotNull(context.cacheDir, context.externalCacheDir),
        progressDatabase = context.getDatabasePath(PROGRESS_DATABASE),
        removeWebViewData = { clearWebViewData() },
    )

    /** Bytes the cache directories are holding. Includes the web view's own. */
    fun cacheBytes(): Long = cacheDirectories.sumOf { it.sizeOnDisk() }

    /** Bytes the reading-position database is holding, journals included. */
    fun historyBytes(): Long =
        File(progressDatabase.parent ?: return 0)
            .listFiles { file -> file.name.startsWith(progressDatabase.name) }
            ?.sumOf { it.length() }
            ?: 0

    /**
     * Empties the cache, and the web view's cookies and origin storage with it.
     *
     * Contents rather than the directory itself: deleting the directory out from under a
     * web view that has it open is how the next page load finds nothing where it expected a
     * writable path.
     *
     * The second half is what the row has always said and never did. "Decoded pages and
     * web-view data" is the string on the Privacy screen in all four languages; the web
     * view's *cache* does live in these directories, but its cookies and per-origin storage
     * do not. That matters more here than on iOS: Readium serves every publication from the
     * one origin `https://readium_package/`, so a cookie set by one book is not scoped to
     * that book -- it is a stable identifier across everything the reader opens, and it
     * survived the clear that told them it was gone.
     *
     * iOS's `StorageUsage.clearCache` removes `WKWebsiteDataStore`'s data in the same call,
     * for the same reason.
     */
    fun clearCache() {
        cacheDirectories.forEach { directory ->
            directory.listFiles()?.forEach { it.deleteRecursively() }
        }
        removeWebViewData()
    }

    private fun File.sizeOnDisk(): Long =
        walkBottomUp().filter { it.isFile }.sumOf { it.length() }

    private companion object {
        const val PROGRESS_DATABASE = "progress.db"

        /**
         * Cookies first, then origin storage, then a flush.
         *
         * `removeAllCookies` writes through asynchronously and nothing here waits on the
         * callback, but the flush is not optional: a process killed before the next
         * automatic flush would bring the cookies back.
         */
        fun clearWebViewData() {
            val cookies = CookieManager.getInstance()
            cookies.removeAllCookies(null)
            cookies.flush()
            WebStorage.getInstance().deleteAllData()
        }
    }
}
