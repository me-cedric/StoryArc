package app.storyarc.core.format

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * What the cover cache alone is holding, as plain files on disk.
 *
 * A plain unit test rather than the instrumented suite [CoverCacheInstrumentedTest] runs:
 * [CoverCache.sizeOnDisk] walks `File`s and touches no `Bitmap`, so it needs no Android
 * framework stub. iOS asserts the same two cases in `CoverCacheTests`.
 */
class CoverCacheSizeTest {

    @get:Rule
    val folder = TemporaryFolder()

    private fun cache(): CoverCache = CoverCache(File(folder.root, "covers"))

    @Test
    fun `an empty cache is nothing on disk`() {
        assertEquals(0L, cache().sizeOnDisk())
    }

    @Test
    fun `a stored file is counted, and clearing counts it away again`() {
        val cache = cache()
        File(folder.root, "covers").mkdirs()
        File(folder.root, "covers/cover.jpg").writeBytes(ByteArray(1_000))

        assertTrue(cache.sizeOnDisk() > 0)

        cache.clear()

        assertEquals(0L, cache.sizeOnDisk())
    }
}
