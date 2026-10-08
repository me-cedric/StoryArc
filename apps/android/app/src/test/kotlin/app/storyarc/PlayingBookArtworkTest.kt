package app.storyarc

import android.graphics.Bitmap
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.playback.PlaybackHost
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `audiobooks-and-playback` task 4.4b: the picture [SessionArtwork] draws is written where the
 * session can load it, for the book being followed and for no other.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37.
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PlayingBookArtworkTest {

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    private fun book(id: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/$id"),
        format = PublicationFormat.M4B,
        displayTitle = id,
        origin = MetadataOrigin.AUTHORITATIVE,
    )

    private val picture: Bitmap = Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888)

    private fun files(): List<File> =
        File(context.cacheDir, "player-artwork").listFiles()?.toList().orEmpty()

    private fun waitForFiles(count: Int): List<File> {
        repeat(200) {
            shadowOf(Looper.getMainLooper()).idle()
            if (files().size >= count) return files()
            Thread.sleep(25)
        }
        return files()
    }

    @Before
    fun clean() {
        File(context.cacheDir, "player-artwork").deleteRecursively()
        PlayingBook.follow(book("sea-room"), ProgressStore.inMemory(context))
    }

    @After
    fun close() {
        PlaybackHost.recordPosition = null
    }

    @Test
    fun `the picture of the followed book is written as a png the session can load`() {
        PlayingBook.artwork(context, book("sea-room").id, picture)

        val written = waitForFiles(1)
        assertEquals(1, written.size)
        assertTrue("a png", written.single().readBytes().take(4) == listOf<Byte>(0x89.toByte(), 0x50, 0x4E, 0x47))
    }

    @Test
    fun `a picture drawn for a book that is not followed is dropped`() {
        PlayingBook.artwork(context, book("long-field").id, picture)

        Thread.sleep(200)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(0, files().size)
    }
}
