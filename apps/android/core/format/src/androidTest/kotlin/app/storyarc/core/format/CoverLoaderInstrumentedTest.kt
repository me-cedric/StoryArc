package app.storyarc.core.format

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Decoding a cover into a `Bitmap`, which needs a device: `ImageDecoder`,
 * `Bitmap` and `PdfRenderer` are all framework stubs on a host JVM.
 *
 * The byte-level half runs as a plain unit test in `CoverLoaderTest`. iOS asserts
 * both together because ImageIO runs on the macOS host.
 */
@RunWith(AndroidJUnit4::class)
class CoverLoaderInstrumentedTest {

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
    fun aCoverComesOutOfEveryContainerThatStoresOne() = runBlocking {
        for (name in listOf(
            "comics/natural-sort.cbz",
            "comics/tar-store.cbt",
            "comics/rar5-store.cbr",
        )) {
            val file = fixture(name)
            val bitmap = CoverLoader.anyCover(PublicationIndexer.index(file), file, 200)
            assertTrue(name, bitmap.width > 0 && bitmap.height > 0)
        }
    }

    @Test
    fun aPdfCoverIsRenderedBecauseItsPagesAreNotStoredAsImages() = runBlocking {
        val file = fixture("comics/image-pages.pdf")
        val bitmap = CoverLoader.anyCover(PublicationIndexer.index(file), file, 150)
        // The page box is 200x300, so a 150-pixel bound gives 100x150.
        assertEquals(100, bitmap.width)
        assertEquals(150, bitmap.height)
    }

    @Test
    fun aCoverIsBoundedByTheSizeItWillBeDrawnAt() = runBlocking {
        // The whole reason the type exists: a 2000x3000 page costs 24 MB of pixels
        // to fill a grid cell a couple of hundred pixels across.
        val file = fixture("comics/large-page.cbz")
        val publication = PublicationIndexer.index(file)

        val thumbnail = CoverLoader.anyCover(publication, file, 200)
        assertEquals(200, maxOf(thumbnail.width, thumbnail.height))

        val larger = CoverLoader.anyCover(publication, file, 600)
        assertEquals(600, maxOf(larger.width, larger.height))
    }
}
