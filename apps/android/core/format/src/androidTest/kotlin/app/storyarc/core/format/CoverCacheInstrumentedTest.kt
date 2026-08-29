package app.storyarc.core.format

import android.graphics.Bitmap
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * The cover cache: what it keeps apart, and what it forgets.
 *
 * Instrumented because it writes and reads a `Bitmap`, which is a framework stub on a host
 * JVM — the same reason `CoverLoaderInstrumentedTest` is. iOS asserts the same four things
 * as plain unit tests, because ImageIO runs on the macOS host.
 */
@RunWith(AndroidJUnit4::class)
class CoverCacheInstrumentedTest {

    private val directory = File(
        InstrumentationRegistry.getInstrumentation().context.cacheDir,
        "cover-cache-test",
    )

    private fun cache() = CoverCache(directory)

    /** A one-colour bitmap. The pixels are not the subject; the filing is. */
    private fun image(): Bitmap =
        Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.RED) }

    @After
    fun tearDown() {
        directory.deleteRecursively()
    }

    @Test
    fun a_stored_cover_reads_back() {
        val cache = cache()

        cache.store(image(), "bone.cbz", 200)

        assertNotNull(cache.bitmap("bone.cbz", 200))
    }

    /**
     * The clause this exists for: "display resolution" is a property of the layout as well
     * as the device, and the grid and the list ask for different sizes.
     */
    @Test
    fun a_cover_cached_for_one_size_is_not_served_for_another() {
        val cache = cache()

        cache.store(image(), "bone.cbz", 200)

        assertNull(cache.bitmap("bone.cbz", 400))
    }

    /**
     * A publication id can carry a path, and a path carries separators. A file name is not
     * where that should be discovered.
     */
    @Test
    fun an_identity_that_looks_like_a_path_is_still_one_file() {
        val cache = cache()
        val identity = "/storage/emulated/0/Comics/../Bone #1.cbz"

        cache.store(image(), identity, 200)

        assertNotNull(cache.bitmap(identity, 200))
    }

    @Test
    fun clearing_forgets_every_cover() {
        val cache = cache()
        cache.store(image(), "a", 200)
        cache.store(image(), "b", 200)

        cache.clear()

        assertNull(cache.bitmap("a", 200))
        assertNull(cache.bitmap("b", 200))
    }

    @Test
    fun asking_for_a_cover_nobody_stored_is_not_an_error() {
        assertNull(cache().bitmap("never-seen", 200))
    }
}
