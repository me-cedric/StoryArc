package app.storyarc.core.persistence

import java.io.File
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * "Clear cache" removes what the Privacy screen says it removes.
 *
 * The security review's rank 19: the row promises "Decoded pages and web-view data" in all
 * four languages, and the code emptied two directories. The web view's *cache* is in those
 * directories; its cookies and per-origin storage are not -- and Readium serves every
 * publication from the single origin `https://readium_package/`, so a cookie one book set is
 * an identifier across all of them, surviving the clear that said it was gone.
 *
 * `CookieManager` and `WebStorage` are platform singletons a JVM test has no WebView for, so
 * the real ones are not called: what is asserted is that clearing asks for them. iOS's
 * `ClearCacheTests` asserts the same two things in the same order.
 */
class ClearCacheTest {

    private val cache = createTempDirectory("clear-cache").toFile()
    private var asked = 0

    private fun usage() = StorageUsage(
        cacheDirectories = listOf(cache),
        progressDatabase = File(cache, "progress.db"),
        removeWebViewData = { asked++ },
    )

    @Test
    fun `clearing empties the cache directory, as it always did`() {
        File(cache, "page.bin").writeBytes(ByteArray(16))
        File(cache, "nested").mkdirs()

        usage().clearCache()

        assertEquals(0, cache.listFiles()?.size)
        assertTrue("the directory itself survives", cache.isDirectory)
        cache.deleteRecursively()
    }

    @Test
    fun `clearing also asks the web view for its cookies and origin storage`() {
        usage().clearCache()

        assertEquals(1, asked)
        cache.deleteRecursively()
    }
}
