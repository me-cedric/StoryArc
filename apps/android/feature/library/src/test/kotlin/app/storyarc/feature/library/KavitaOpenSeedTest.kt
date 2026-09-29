package app.storyarc.feature.library

import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A chapter opened from the Kavita browser starts where the server says the reader is.
 *
 * The field report: Continue, a chapter row and a reading-list entry all opened at page one,
 * and closing the chapter then reported page one back, moving the server behind. iOS's
 * `KavitaOpenSeedTests` asserts the same cases.
 *
 * `sdk = [34]` for the reason `KavitaCardFactsTest` gives.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class KavitaOpenSeedTest {

    private fun progress() = ProgressStore.inMemory(ApplicationProvider.getApplicationContext())

    private fun book(format: PublicationFormat, name: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/Kavita/$name"),
        format = format,
        displayTitle = "Chapter",
        origin = MetadataOrigin.EMBEDDED,
    )

    @Test
    fun `a comic is seeded at the server's page, stamped as synchronised`() = runBlocking {
        val progress = progress()
        val comic = book(PublicationFormat.CBZ, "one.cbz")

        seedKavitaOpen(comic, pagesRead = 4, pages = 10, progress = progress)

        val found = progress.progress(comic.identity)
        assertEquals(ReadingPosition.Page(3, 10), found?.position)
        assertEquals(
            "the server already holds this position",
            found?.position?.fraction,
            found?.syncedPosition?.fraction,
        )
    }

    @Test
    fun `an EPUB is seeded as a fraction its reader opens at, not as a page`() = runBlocking {
        val progress = progress()
        val epub = book(PublicationFormat.EPUB, "two.epub")

        seedKavitaOpen(epub, pagesRead = 6, pages = 11, progress = progress)

        val position = progress.progress(epub.identity)?.position
        assertTrue("an EPUB seeded as $position, which its reader cannot open", position is ReadingPosition.Reflowable)
        assertEquals(ReadingPosition.Page(5, 11).fraction, position?.fraction ?: -1.0, 0.0)
    }

    @Test
    fun `a chapter this device already holds a position for is left alone`() = runBlocking {
        val progress = progress()
        val comic = book(PublicationFormat.CBZ, "three.cbz")
        progress.save(
            ReadingProgress(identity = comic.identity, position = ReadingPosition.Page(8, 10), updatedAtEpochMillis = 0),
        )

        seedKavitaOpen(comic, pagesRead = 2, pages = 10, progress = progress)

        assertEquals(ReadingPosition.Page(8, 10), progress.progress(comic.identity)?.position)
    }
}
