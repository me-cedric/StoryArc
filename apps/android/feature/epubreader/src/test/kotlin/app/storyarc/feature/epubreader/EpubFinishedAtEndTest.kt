package app.storyarc.feature.epubreader

import android.os.Looper
import app.storyarc.core.model.PageTransition
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.persistence.ProgressStore
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * An EPUB is recorded finished on the last page of its last resource.
 *
 * The field report: Readium's locator names where the visible page starts, so a short last
 * page never crossed the 0.999 threshold and the book was never recorded finished. iOS
 * asserts the same rule in `EpubFinishedAtEndTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class EpubFinishedAtEndTest {

    private val order = listOf("OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml")

    @Test
    fun `the last page of the last resource is the end of the book`() {
        assertTrue(isLastPage(2, 3, "OEBPS/ch2.xhtml#end", order, PageTransition.SLIDE))
    }

    @Test
    fun `the page before it is not`() {
        assertFalse(isLastPage(1, 3, "OEBPS/ch2.xhtml", order, PageTransition.SLIDE))
    }

    @Test
    fun `the last page of an earlier resource is not`() {
        assertFalse(isLastPage(2, 3, "OEBPS/ch1.xhtml", order, PageTransition.SLIDE))
    }

    @Test
    fun `scroll mode reports a whole resource as one page, so it says nothing`() {
        assertFalse(isLastPage(0, 1, "OEBPS/ch2.xhtml", order, PageTransition.VERTICAL_SCROLL))
    }

    /** The committed fixture corpus, from this module's own directory rather than a walk. */
    private val corpus: File = File(
        requireNotNull(System.getProperty("storyarc.epubreader.projectDir")) {
            "storyarc.epubreader.projectDir is not set -- see this module's build.gradle.kts"
        },
    ).resolve("../../../..").canonicalFile.resolve("packages/test-fixtures")

    @Test
    fun `the reader records the book finished when its last page is shown`() {
        val file = corpus.resolve("ebooks/fixture.epub")
        val identity = PublicationIdentity(normalizedPath = file.absolutePath)
        val progress = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        val model = EpubReaderViewModel(
            application = RuntimeEnvironment.getApplication(),
            location = file.absolutePath,
            identity = identity,
            progress = progress,
        )
        val publication = requireNotNull(runBlocking { model.open() }) { "fixture failed to open" }
        val last = publication.readingOrder.last()
        // Starts at 96 % of the book: the locator's own total is far from the threshold.
        val locator = Locator(
            href = last.url(),
            mediaType = requireNotNull(last.mediaType),
            locations = Locator.Locations(progression = 0.5, totalProgression = 0.96),
        )

        model.pageShown(pageIndex = 1, totalPages = 3, locator = locator)
        assertNull("a page before the last must not finish the book", recorded(progress, identity))

        model.pageShown(pageIndex = 2, totalPages = 3, locator = locator)
        assertEquals(true, waitForRecord(progress, identity))
    }

    private fun recorded(progress: ProgressStore, identity: PublicationIdentity): Boolean? {
        shadowOf(Looper.getMainLooper()).idle()
        return runBlocking { progress.progress(identity)?.isFinished }
    }

    /** The save runs on Room's own executor, so the check waits for it to land. */
    private fun waitForRecord(progress: ProgressStore, identity: PublicationIdentity): Boolean? {
        repeat(ATTEMPTS) {
            recorded(progress, identity)?.let { return it }
            Thread.sleep(WAIT_MILLIS)
        }
        return recorded(progress, identity)
    }

    private companion object {
        const val ATTEMPTS = 50
        const val WAIT_MILLIS = 20L
    }
}
