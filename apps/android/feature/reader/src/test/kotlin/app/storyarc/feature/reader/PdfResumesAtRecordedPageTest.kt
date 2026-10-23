package app.storyarc.feature.reader

import android.graphics.pdf.PdfRenderer
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.persistence.ProgressStore
import java.io.File
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements

/**
 * A PDF read to page 3 opens at page 3 (task 28.2 of `close-the-audited-gaps`).
 *
 * The pager seeds its position from [ReaderViewModel.initialIndex] the moment the page list
 * is not empty, and jumps once. Before the fix, `openPdf` published the page list, then read
 * the text layer, then read the recorded position. The pager jumped to page one in that gap,
 * recorded page one, and the hero was gone from Home. So the recorded page must be set before
 * the page list is published. An archive already does this in `applyOpenedArchive`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], shadows = [FivePagePdfRenderer::class])
class PdfResumesAtRecordedPageTest {

    private fun fixture(): File {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error("$MODULE_DIRECTORY is unset. Run this test through Gradle.")
        val file = File(module, FIXTURE).canonicalFile
        if (!file.isFile) error("$FIXTURE is not under ${module.absolutePath} -- has it moved?")
        return file
    }

    @Test
    fun `the recorded page is set before the page list is published`() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val file = fixture()
        val publication = Publication(
            identity = PublicationIdentity(normalizedPath = file.path),
            format = PublicationFormat.PDF,
            displayTitle = "Field Notes",
            origin = MetadataOrigin.INFERRED,
        )
        val store = ProgressStore.inMemory(context)
        store.save(
            ReadingProgress(
                identity = publication.identity,
                position = ReadingPosition.Page(2, 5),
                updatedAtEpochMillis = 1L,
            ),
        )
        val model = ReaderViewModel(publication, context.contentResolver, file.path, progress = store)

        // What the pager reads at the moment it gets a page count.
        var atFirstPages: Int? = null
        val watch = launch(start = CoroutineStart.UNDISPATCHED) {
            model.pages.first { it.isNotEmpty() }
            atFirstPages = model.initialIndex
        }
        model.open(256)
        if (model.pages.value.isEmpty()) {
            watch.cancel()
            fail("the fixture did not open: ${model.failure.value}")
        }
        watch.join()
        assertEquals("the pager seeds from initialIndex when the pages arrive", 2, atFirstPages)
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val FIXTURE = "../../../../packages/test-fixtures/comics/text-pages.pdf"
    }
}

/**
 * Robolectric has no pdfium, so a real `PdfRenderer` reports no pages and the reader shows an
 * empty publication. The fixture has five pages; this says so, and nothing else.
 */
@Implements(PdfRenderer::class)
class FivePagePdfRenderer {
    @Implementation
    fun getPageCount(): Int = 5
}
