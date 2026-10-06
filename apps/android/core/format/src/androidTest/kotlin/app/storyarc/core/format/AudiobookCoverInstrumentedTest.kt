package app.storyarc.core.format

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Reading an audiobook's own embedded artwork, which needs a device:
 * `MediaMetadataRetriever` is a framework stub on a host JVM, the same reason
 * `CoverLoaderInstrumentedTest`'s bitmap half is.
 *
 * Task 16.9. The folder half — a loose `cover.jpg`/`cover.png` beside a folder's own
 * tracks — touches nothing from the framework and is asserted as a plain unit test in
 * `AudiobookCoverTest` instead; this file is only for the one call that is not.
 */
@RunWith(AndroidJUnit4::class)
class AudiobookCoverInstrumentedTest {

    private fun fixture(name: String): File {
        val context = InstrumentationRegistry.getInstrumentation().context
        val target = File(context.cacheDir, name.substringAfterLast('/'))
        if (!target.exists()) {
            context.assets.open(name).use { input ->
                target.outputStream().use(input::copyTo)
            }
        }
        return target
    }

    @Test
    fun anM4bsOwnCovrAtomIsReadAsItsCover() {
        val data = AudiobookCover.embedded(fixture("audiobooks/with-cover.m4b").path)
        assertNotNull(data)
        assertTrue((data?.size ?: 0) > 0)
    }

    @Test
    fun theSameCoverAsAnId3ApicFrameIsReadIdentically() {
        val data = AudiobookCover.embedded(fixture("audiobooks/with-cover.mp3").path)
        assertNotNull(data)
        assertTrue((data?.size ?: 0) > 0)
    }

    @Test
    fun anAudiobookWithNoEmbeddedArtworkNamesNoCover() {
        val data = AudiobookCover.embedded(fixture("audiobooks/chaptered.m4b").path)
        assertNull(data)
    }

    // `: Unit` is load-bearing. An expression body returns whatever its last expression does,
    // and this block ends with `deleteRecursively()`, which answers a `Boolean`. JUnit 4
    // validates that a `@Test` method is void and refuses the whole class when one is not, so
    // without this the suite does not fail -- it does not run.
    @Test
    fun indexingAnM4bWithACoverWritesItAndRecordsThePath(): Unit = runBlocking {
        val cacheDir = File(
            InstrumentationRegistry.getInstrumentation().context.cacheDir,
            "audiobook-cover-instrumented-test",
        )
        cacheDir.deleteRecursively()
        val file = fixture("audiobooks/with-cover.m4b")

        val publication = PublicationIndexer.index(file, coverCacheDir = cacheDir)

        val path = publication.coverPath
        assertNotNull(path)
        assertTrue(File(path!!).isFile)
        assertTrue(File(path).readBytes().isNotEmpty())

        cacheDir.deleteRecursively()
    }
}
