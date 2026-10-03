package app.storyarc.feature.reader

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * `offline-downloads` dl-core 1.7: a streamed open that fails is replaced by the copy that
 * lands, rather than left showing the ordinary failure for ever.
 *
 * Before the fix, [ReaderViewModel.open] left `archive` null on any failure and
 * `adoptLocalCopy` returned `false` whenever `archive` was null -- so a server with no range
 * support left the reader on `reader_cannot_open` even after the download finished. iOS's
 * `ReaderDownloadWaitTests` makes the same claims.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReaderDownloadWaitTest {

    private fun fixture(name: String): File {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error("$MODULE_DIRECTORY is unset. Run this test through Gradle.")
        val file = File(module, "$CORPUS/$name").canonicalFile
        if (!file.isFile) error("$name is not under ${module.absolutePath}/$CORPUS -- has it moved?")
        return file
    }

    private fun model(path: String, isDownloadPending: () -> Boolean): ReaderViewModel = ReaderViewModel(
        publication = Publication(
            identity = PublicationIdentity(normalizedPath = path),
            format = PublicationFormat.CBZ,
            displayTitle = "Waiting Room",
            origin = MetadataOrigin.INFERRED,
        ),
        resolver = RuntimeEnvironment.getApplication().contentResolver,
        path = path,
        isDownloadPending = isDownloadPending,
    )

    /** A path nothing will ever open, standing in for a stream with no range support. */
    private fun unopenablePath(): String =
        File(System.getProperty("java.io.tmpdir"), "dl-core-1-7-missing.cbz").absolutePath

    @Test
    fun `a failed open waits rather than failing while the download is still on its way`() {
        val model = model(unopenablePath()) { true }
        runBlocking { model.open(256) }

        assertTrue(model.isWaitingForDownload.value)
        assertEquals(null, model.failure.value)
    }

    @Test
    fun `a failed open fails ordinarily once the download itself has failed`() {
        val model = model(unopenablePath()) { false }
        runBlocking { model.open(256) }

        assertFalse(model.isWaitingForDownload.value)
        assertEquals(R.string.reader_cannot_open, model.failure.value)
    }

    @Test
    fun `the wait ends as the ordinary failure when the download fails after it began`() {
        var isPending = true
        val model = model(unopenablePath()) { isPending }
        runBlocking { model.open(256) }
        assertTrue(model.isWaitingForDownload.value)

        model.endWaitIfDownloadStopped()
        assertTrue("A download still on its way must keep the wait.", model.isWaitingForDownload.value)

        isPending = false
        model.endWaitIfDownloadStopped()

        assertFalse(model.isWaitingForDownload.value)
        assertEquals(R.string.reader_cannot_open, model.failure.value)
    }

    @Test
    fun `adoptLocalCopy opens the arrived file directly, with nothing to adopt into`() {
        val model = model(unopenablePath()) { true }
        runBlocking {
            model.open(256)
            assertTrue(model.isWaitingForDownload.value)

            val adopted = model.adoptLocalCopy(
                RuntimeEnvironment.getApplication().contentResolver,
                fixture("natural-sort.cbz").absolutePath,
            )

            assertTrue(adopted)
            assertFalse(model.isWaitingForDownload.value)
            assertTrue(model.pages.value.isNotEmpty())
            assertEquals(null, model.failure.value)
        }
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val CORPUS = "../../../../packages/test-fixtures/comics"
    }
}
