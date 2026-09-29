package app.storyarc.feature.epubreader

import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * A finished book reopens at its beginning, not at the page it was marked finished on.
 *
 * The field report: a book the reader finished, then opened again from the library, came
 * back on its last page. [EpubReaderViewModel.initialLocator] read the stored locator
 * whether or not the record was finished, the same as the comic and PDF readers used to.
 *
 * iOS mirrors this in `EpubReaderModelTests`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class EpubFinishedResumeTest {

    private val identity = PublicationIdentity(normalizedPath = "/nowhere.epub")
    private val locatorJson = """{"href":"/chapter-1.xhtml","type":"text/html",
        "locations":{"totalProgression":0.87}}"""

    private fun reader(progress: ProgressStore) = EpubReaderViewModel(
        application = RuntimeEnvironment.getApplication(),
        location = "/nowhere.epub",
        identity = identity,
        progress = progress,
    )

    @Test
    fun `a finished record is not resumed`() = runTest {
        val progress = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        progress.save(
            ReadingProgress(
                identity = identity,
                position = ReadingPosition.Reflowable(progression = 0.87, locator = locatorJson),
                isFinished = true,
                updatedAtEpochMillis = 0,
            ),
        )

        assertNull(reader(progress).initialLocator())
    }

    @Test
    fun `an unfinished record is resumed, so the fix above is not a no-op`() = runTest {
        val progress = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        progress.save(
            ReadingProgress(
                identity = identity,
                position = ReadingPosition.Reflowable(progression = 0.87, locator = locatorJson),
                isFinished = false,
                updatedAtEpochMillis = 0,
            ),
        )

        val locator = reader(progress).initialLocator()
        assertEquals("/chapter-1.xhtml", locator?.href?.toString())
    }

    /** The committed fixture corpus, from this module's own directory rather than a walk. */
    private val corpus: File = File(
        requireNotNull(System.getProperty("storyarc.epubreader.projectDir")) {
            "storyarc.epubreader.projectDir is not set -- see this module's build.gradle.kts"
        },
    ).resolve("../../../..").canonicalFile.resolve("packages/test-fixtures")

    @Test
    fun `a position with no locator -- a pull's own kind -- still opens at its fraction`() = runTest {
        // The defect: `KavitaSync.pull` used to write a page number over an EPUB's own
        // position, and a page is not a locator this reader can open -- so the book
        // opened at its very first page regardless of how far a server said the reader
        // had gone. `KavitaExchange.position(pagesRead:pages:like:)` now writes a
        // fraction with an empty locator instead, which is exactly this shape.
        val file = corpus.resolve("ebooks/fixture.epub")
        val fileIdentity = PublicationIdentity(normalizedPath = file.absolutePath)
        val progress = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        progress.save(
            ReadingProgress(
                identity = fileIdentity,
                position = ReadingPosition.Reflowable(progression = 0.6, locator = ""),
                isFinished = false,
                updatedAtEpochMillis = 0,
            ),
        )
        val model = EpubReaderViewModel(
            application = RuntimeEnvironment.getApplication(),
            location = file.absolutePath,
            identity = fileIdentity,
            progress = progress,
        )

        assertTrue("fixture failed to open", model.open() != null)
        val locator = model.initialLocator()

        assertTrue("opened at the first page despite the recorded fraction", locator != null)
    }
}
