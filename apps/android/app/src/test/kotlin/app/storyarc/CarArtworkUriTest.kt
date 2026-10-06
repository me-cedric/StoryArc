package app.storyarc

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Task 16.9: the artwork `PublicationIndexer` extracts reaches the car shelf and the media
 * session, instead of stopping at the app's own player.
 *
 * `CarShelf.carBook` answered every row with no artwork, and the reason it gave — that
 * `Publication.coverPath` names an entry inside the container — stopped being true when
 * 16.9 began writing an audiobook's embedded artwork to a file of its own.
 *
 * Robolectric for `Uri.fromFile` alone: the rule is pure, and the one platform call in it
 * is the form media3 fetches artwork from.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CarArtworkUriTest {

    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun `an extracted cover reaches the row as a file URI`() {
        val cover = folder.newFile("sea-room.png")

        assertEquals("file://${cover.path}", carArtworkUri(cover.path))
    }

    @Test
    fun `a publication with no recorded cover carries no artwork`() {
        assertNull(carArtworkUri(null))
    }

    @Test
    fun `a cover the system has reclaimed leaves the row with no artwork`() {
        val gone = File(folder.root, "reclaimed.png").path

        assertNull(carArtworkUri(gone))
    }

    @Test
    fun `a directory is not a cover`() {
        val directory = folder.newFolder("covers")

        assertNull(carArtworkUri(directory.path))
    }
}
