package app.storyarc.feature.library

import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.KavitaOrigin
import app.storyarc.core.persistence.KavitaProgressStore
import app.storyarc.core.persistence.ProgressStore
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

/**
 * Which local record a server's chapter is, when the two do not agree on a path.
 *
 * A pull has a chapter id and the store keys on a publication identity. The browser's
 * chapter-to-publication table bridges them, and it holds whichever publication id the
 * chapter was *opened* as -- which is not the id of the copy the record was written under
 * once the same chapter has been reached two ways. ADR-0006's first rule is what closes
 * that, and this is the first assertion [KavitaSync] has ever had.
 * iOS's `KavitaPullIdentityTests` asserts the same cases.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class KavitaPullIdentityTest {

    private val source: UUID = UUID.randomUUID()

    private fun context() = ApplicationProvider.getApplicationContext<android.content.Context>()

    private fun kavita(): KavitaProgressStore = KavitaProgressStore.open(context())

    private fun progress(): ProgressStore = ProgressStore.inMemory(context())

    private fun origin(chapterId: Int = 42) = KavitaOrigin(
        sourceId = source.toString(),
        libraryId = 1,
        seriesId = 7,
        volumeId = 3,
        chapterId = chapterId,
    )

    private fun chapter(id: Int = 42, pagesRead: Int = 8) =
        KavitaChapter(id = id, number = "1", pages = 10, pagesRead = pagesRead)

    @Test
    fun `a chapter whose record was written under another path is still found`() = runTest {
        // The reader kept the chapter offline, so the record carries the download's path.
        // The browser then opened it from the server, and remembers that copy's id. Only
        // the chapter id is common to both.
        val progress = progress()
        val kavita = kavita()
        progress.save(
            ReadingProgress(
                PublicationIdentity(
                    serverIdentifier = PublicationIdentity.ServerIdentifier(source, "42"),
                    normalizedPath = "/downloads/Bone 01.cbz",
                ),
                ReadingPosition.Page(4, 10),
                false,
                updatedAtEpochMillis = 1_000,
            ),
        )
        kavita.remember("path:/caches/Kavita/42/Bone 1.cbz", origin())

        KavitaSync.pull(listOf(chapter()), kavita, progress)

        val read = progress.progress(
            PublicationIdentity(
                serverIdentifier = PublicationIdentity.ServerIdentifier(source, "42"),
            ),
        )
        assertEquals("the server was further ahead", ReadingPosition.Page(7, 10), read?.position)
        assertEquals("one chapter, one record", 1, progress.recent(10).size)
    }

    @Test
    fun `a chapter this device has never opened is left alone`() = runTest {
        // The position is real and the publication is not. Inventing an identity for it
        // would be inventing a reading.
        val progress = progress()

        KavitaSync.pull(listOf(chapter(id = 99)), kavita(), progress)

        assertTrue(progress.recent(10).isEmpty())
    }

    @Test
    fun `a record written before server identifiers existed is still found by its id`() = runTest {
        // Every position in the shipped app was written against a path alone, and the
        // browser remembered that same path. The fallback is the only route to those.
        val progress = progress()
        val kavita = kavita()
        progress.save(
            ReadingProgress(
                PublicationIdentity(normalizedPath = "/caches/Kavita/42/Bone 1.cbz"),
                ReadingPosition.Page(4, 10),
                false,
                updatedAtEpochMillis = 1_000,
            ),
        )
        kavita.remember("path:/caches/Kavita/42/Bone 1.cbz", origin())

        KavitaSync.pull(listOf(chapter()), kavita, progress)

        val read = progress.progress(
            PublicationIdentity(normalizedPath = "/caches/Kavita/42/Bone 1.cbz"),
        )
        assertEquals(ReadingPosition.Page(7, 10), read?.position)
    }
}
