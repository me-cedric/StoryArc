package app.storyarc.feature.library

import android.app.Application
import android.graphics.Bitmap
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Task 22.2's own correction: a server shelf's card is drawn "through the authenticated
 * client and the cover cache", and neither `HomeShelfArtwork` nor the Shelves screen's
 * `ServerShelfCard` used one — every appearance of either card asked the server again and
 * decoded the answer again. [LibraryViewModel.serverCover] is the one door both now go
 * through, so this is asserted once here rather than by re-fetching an emulator's Kavita
 * mock from two different screens.
 *
 * `GraphicsMode.NATIVE` for the reason [DownloadsCoverlessWellTest] gives: Robolectric's
 * legacy graphics measure a decoded bitmap as a fixed placeholder, which would make a real
 * decode and a cache hit indistinguishable.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class ServerCoverCacheTest {

    private fun viewModel() =
        LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())

    private fun onePixelPng(): ByteArray {
        val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.MAGENTA)
        val out = java.io.ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }

    @Test
    fun `a cover fetched once is not asked of the server a second time`() = runTest {
        val library = viewModel()
        var fetches = 0

        val first = library.serverCover(id = "srv:server-a:series:42", maxPixelSize = 180) {
            fetches++
            onePixelPng()
        }
        assertNotNull("the first call should have decoded something to cache", first)
        assertEquals(1, fetches)

        // A fresh `LibraryViewModel` — a different card composed after the first one left
        // composition, or the app relaunched — reads the same disk directory `cacheDir/covers`
        // names, which is the property this cache is for: it survives past the composable
        // that first asked.
        val second = viewModel().serverCover(id = "srv:server-a:series:42", maxPixelSize = 180) {
            fetches++
            onePixelPng()
        }

        assertEquals(
            "a cover already on disk was fetched from the server again",
            1,
            fetches,
        )
        assertNotNull(second)
    }

    @Test
    fun `two servers answering the same small integer do not share a cache entry`() = runTest {
        val library = viewModel()
        var serverAFetches = 0
        var serverBFetches = 0

        library.serverCover(id = "srv:server-a:series:1", maxPixelSize = 180) {
            serverAFetches++
            onePixelPng()
        }
        library.serverCover(id = "srv:server-b:series:1", maxPixelSize = 180) {
            serverBFetches++
            onePixelPng()
        }

        assertEquals(
            "server B's own request for series 1 was answered from server A's cache entry",
            1,
            serverBFetches,
        )
        assertEquals(1, serverAFetches)
    }

    @Test
    fun `a fetch that fails caches nothing, so the next appearance tries again`() = runTest {
        val library = viewModel()

        val failed = library.serverCover(id = "srv:server-a:series:99", maxPixelSize = 180) {
            error("the server is away")
        }
        assertNull(failed)

        var secondAttemptRan = false
        library.serverCover(id = "srv:server-a:series:99", maxPixelSize = 180) {
            secondAttemptRan = true
            onePixelPng()
        }

        assertEquals(true, secondAttemptRan)
    }
}
