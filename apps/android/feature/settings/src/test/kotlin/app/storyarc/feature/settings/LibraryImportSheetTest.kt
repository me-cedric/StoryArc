package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.ImportPreviewLine
import app.storyarc.core.model.ImportedShelf
import app.storyarc.core.model.LibraryDocumentCoder
import app.storyarc.core.model.LibraryDocumentFailure
import app.storyarc.core.model.LibrarySnapshot
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.Shelves
import app.storyarc.core.model.previewLines
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `library-portability` tasks 3.1, 5.4 and 6.8: the import flow, from the picked file to what the
 * reader is told. iOS's `LibraryImportSheetTests` asserts the same rows.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h800dp")
class LibraryImportSheetTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun string(id: Int, vararg args: Any) = context.getString(id, *args)

    private fun isDrawn(text: String) =
        compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    private fun show(state: LibraryImportState) {
        compose.setContent {
            StoryArcTheme { LibraryImportContent(state = state, onImport = {}, onClose = {}) }
        }
        compose.waitForIdle()
    }

    private fun previewOf(state: LibraryImportState) =
        (state.phase as? ImportPhase.Preview)?.preview

    // Nothing changes first.

    @Test
    fun `reading a file plans the import and changes nothing`() = runBlocking {
        val device = TransferDevice(context)
        val before = device.archive.snapshot()
        val state = LibraryImportState()

        state.load(MemoryFile(TransferLibrary.documentText(sealed = true)), device.transfer)

        val preview = requireNotNull(previewOf(state))
        assertEquals(listOf("Comics NAS", "Kavita"), preview.plan.sourcesToAdd)
        assertEquals(before, device.archive.snapshot())
        assertTrue(device.secrets.held.isEmpty())
    }

    @Test
    fun `confirming imports, tells the app once, and reports what it did`() = runBlocking {
        val device = TransferDevice(context)
        val state = LibraryImportState()
        state.load(MemoryFile(TransferLibrary.documentText()), device.transfer)
        val told = mutableListOf<Any>()

        state.confirm(device.transfer, skippingSecrets = false) { told += it }

        val done = state.phase as ImportPhase.Done
        assertEquals(listOf<Any>(done.outcome), told)
        assertEquals(
            listOf("Comics NAS", "Kavita"),
            device.archive.snapshot().sources.sources.map { it.displayName },
        )
        assertEquals(listOf("Comics NAS", "Kavita"), done.outcome.sourcesNeedingSignIn)
    }

    // What the preview draws (6.8).

    @Test
    fun `the preview draws the pin notice naming the host and the source`() = runBlocking {
        val device = TransferDevice(context)
        val state = LibraryImportState()
        state.load(MemoryFile(TransferLibrary.documentText()), device.transfer)

        show(state)

        assertTrue(isDrawn(string(R.string.transfer_line_pins)))
        assertTrue(isDrawn(string(R.string.transfer_line_pin, "nas.local", "Comics NAS")))
        assertTrue(isDrawn(string(R.string.transfer_line_pins_note)))
    }

    @Test
    fun `the preview draws how many members a merged shelf gains`() = runBlocking {
        val shelf = PublicationCollection(name = "Image Comics", members = setOf("path:/a.cbz"))
        val device = TransferDevice(context).holding(LibrarySnapshot(shelves = Shelves(collections = listOf(shelf))))
        val carried = TransferLibrary.library.copy(
            shelves = Shelves(
                collections = listOf(shelf.copy(members = setOf("path:/a.cbz", "path:/b.cbz"))),
            ),
        )
        val state = LibraryImportState()
        state.load(MemoryFile(TransferLibrary.documentText(carried)), device.transfer)

        show(state)

        val merged = ImportedShelf("Image Comics", 1)
        val lines = requireNotNull(previewOf(state)).plan.previewLines()
        assertTrue(lines.contains(ImportPreviewLine.ShelvesMerged(listOf(merged))))
        assertTrue(isDrawn("Image Comics"))
        assertTrue(isDrawn(context.resources.getQuantityString(R.plurals.transfer_line_merged_added, 1, 1)))
    }

    // A refusal is by name.

    @Test
    fun `a newer version is refused by name on the screen, and the device is unchanged`() = runBlocking {
        val device = TransferDevice(context)
        val before = device.archive.snapshot()
        val state = LibraryImportState()

        state.load(MemoryFile(TransferLibrary.documentText(version = 9)), device.transfer)

        assertEquals(
            ImportPhase.Refused(ImportRefusal.Document(LibraryDocumentFailure.NewerThanThisApp(9, 1))),
            state.phase,
        )
        show(state)
        assertTrue(isDrawn(string(R.string.transfer_refused_title)))
        assertTrue(isDrawn(string(R.string.transfer_refused_newer, 9, 1)))
        assertEquals(before, device.archive.snapshot())
    }

    @Test
    fun `a file that is not a library file is refused by name`() = runBlocking {
        val state = LibraryImportState()

        state.load(MemoryFile("hello"), TransferDevice(context).transfer)

        assertEquals(
            ImportPhase.Refused(ImportRefusal.Document(LibraryDocumentFailure.NotALibraryDocument)),
            state.phase,
        )
        show(state)
        assertTrue(isDrawn(string(R.string.transfer_refused_not_a_document)))
    }

    @Test
    fun `a file over the limit is refused from its size before it is read`() = runBlocking {
        val state = LibraryImportState()
        val file = MemoryFile("{}", reportedSize = LibraryDocumentCoder.MAXIMUM_BYTES + 1)

        state.load(file, TransferDevice(context).transfer)

        assertEquals(
            ImportPhase.Refused(
                ImportRefusal.Document(
                    LibraryDocumentFailure.TooLarge(
                        LibraryDocumentCoder.MAXIMUM_BYTES + 1,
                        LibraryDocumentCoder.MAXIMUM_BYTES,
                    ),
                ),
            ),
            state.phase,
        )
        assertEquals("not a byte of it was read", 0, file.opened)
    }

    @Test
    fun `a file that reports no size is read only as far as the limit allows`() = runBlocking {
        val state = LibraryImportState()
        val endless = object : PickedFile {
            override fun size(): Long? = null

            override fun open() = object : java.io.InputStream() {
                var served = 0L

                override fun read(): Int {
                    served += 1
                    return ' '.code
                }

                override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
                    served += length
                    buffer.fill(' '.code.toByte(), offset, offset + length)
                    return length
                }
            }
        }

        state.load(endless, TransferDevice(context).transfer)

        val refused = state.phase as ImportPhase.Refused
        assertTrue(refused.refusal is ImportRefusal.Document)
        assertTrue((refused.refusal as ImportRefusal.Document).failure is LibraryDocumentFailure.TooLarge)
    }

    @Test
    fun `a file that cannot be opened says so and changes nothing`() = runBlocking {
        val state = LibraryImportState()

        state.load(MemoryFile("{}", unopenable = true), TransferDevice(context).transfer)

        assertEquals(ImportPhase.Refused(ImportRefusal.Unopened), state.phase)
        show(state)
        assertTrue(isDrawn(string(R.string.transfer_refused_unopened)))
    }

    @Test
    fun `a provider that throws while it is asked is a file that cannot be opened, not a crash`() = runBlocking {
        val state = LibraryImportState()
        val throwing = object : PickedFile {
            override fun size(): Long = throw IllegalStateException("the provider went away")

            override fun open(): java.io.InputStream? = null
        }

        state.load(throwing, TransferDevice(context).transfer)

        assertEquals(ImportPhase.Refused(ImportRefusal.Unopened), state.phase)
    }

    // The passphrase (5.4).

    @Test
    fun `a document with secrets asks for the passphrase and one without does not`() = runBlocking {
        val device = TransferDevice(context)
        val sealed = LibraryImportState().apply {
            load(MemoryFile(TransferLibrary.documentText(sealed = true)), device.transfer)
        }
        show(sealed)
        assertTrue(isDrawn(string(R.string.transfer_import_secrets)))
        assertTrue(isDrawn(string(R.string.transfer_passphrase)))
        assertTrue(isDrawn(string(R.string.transfer_import_without_secrets)))
    }

    @Test
    fun `a document without secrets draws no passphrase field`() = runBlocking {
        val device = TransferDevice(context)
        val plain = LibraryImportState().apply {
            load(MemoryFile(TransferLibrary.documentText()), device.transfer)
        }

        show(plain)

        assertFalse(isDrawn(string(R.string.transfer_passphrase)))
        assertFalse(isDrawn(string(R.string.transfer_import_secrets)))
    }

    @Test
    fun `a wrong passphrase is stated and the reader may try again`() = runBlocking {
        val device = TransferDevice(context)
        val before = device.archive.snapshot()
        val state = LibraryImportState()
        state.load(MemoryFile(TransferLibrary.documentText(sealed = true)), device.transfer)

        state.passphrase = "not it"
        state.confirm(device.transfer, skippingSecrets = false) {}

        assertNotNull(previewOf(state))
        assertTrue(state.passphraseRefused)
        assertEquals(before, device.archive.snapshot())

        state.passphrase = TransferLibrary.vector.passphrase
        state.confirm(device.transfer, skippingSecrets = false) {}

        val done = state.phase as ImportPhase.Done
        assertEquals(2, done.outcome.secretsWritten)
        assertEquals(2, device.secrets.held.size)
        assertEquals("", state.passphrase)
    }

    @Test
    fun `the wrong passphrase sentence is drawn`() = runBlocking {
        val device = TransferDevice(context)
        val state = LibraryImportState()
        state.load(MemoryFile(TransferLibrary.documentText(sealed = true)), device.transfer)
        state.passphrase = "not it"
        state.confirm(device.transfer, skippingSecrets = false) {}

        show(state)

        assertTrue(isDrawn(string(R.string.transfer_import_wrong)))
    }

    @Test
    fun `skipping imports the rest and the result names the sources that need a sign-in`() = runBlocking {
        val device = TransferDevice(context)
        val state = LibraryImportState()
        state.load(MemoryFile(TransferLibrary.documentText(sealed = true)), device.transfer)

        state.confirm(device.transfer, skippingSecrets = true) {}

        val done = state.phase as ImportPhase.Done
        assertEquals(listOf("Comics NAS", "Kavita"), done.outcome.sourcesNeedingSignIn)
        assertTrue(device.secrets.held.isEmpty())
        show(state)
        assertTrue(isDrawn("Comics NAS"))
        assertTrue(isDrawn(context.resources.getQuantityString(R.plurals.transfer_done_sign_in, 2, 2)))
    }

    // Conflicts, once.

    @Test
    fun `a position both devices moved is named once with both positions`() = runBlocking {
        val identity = PublicationIdentity(contentDigest = "d1", normalizedPath = "/a.cbz")
        val carried = TransferLibrary.library.copy(
            progress = listOf(
                ReadingProgress(
                    identity = identity,
                    position = ReadingPosition.Page(12, 40),
                    updatedAtEpochMillis = 1_767_100_000_000L,
                ),
            ),
        )
        val device = TransferDevice(context).holding(
            LibrarySnapshot(
                progress = listOf(
                    ReadingProgress(
                        identity = identity,
                        position = ReadingPosition.Page(30, 40),
                        updatedAtEpochMillis = 1_767_200_000_000L,
                        syncedPosition = ReadingPosition.Page(1, 40),
                    ),
                ),
            ),
        )
        val state = LibraryImportState()
        state.load(MemoryFile(TransferLibrary.documentText(carried)), device.transfer)

        state.confirm(device.transfer, skippingSecrets = true) {}

        val done = state.phase as ImportPhase.Done
        assertEquals(1, done.outcome.conflicts.size)
        show(state)
        assertTrue(isDrawn(string(R.string.transfer_done_conflict_one, "Page 31 of 40", "Page 13 of 40")))
    }

    @Test
    fun `a position is worded as a page where the count is known and a percentage otherwise`() {
        compose.setContent {
            StoryArcTheme {
                androidx.compose.foundation.layout.Column {
                    androidx.compose.material3.Text(positionWords(ReadingPosition.Page(11, 40)))
                    androidx.compose.material3.Text(positionWords(ReadingPosition.Reflowable(0.375, "{}")))
                }
            }
        }
        compose.waitForIdle()

        assertTrue(isDrawn("Page 12 of 40"))
        assertTrue(isDrawn("38%"))
    }
}
