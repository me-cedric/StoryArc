package app.storyarc.feature.settings

import android.content.Context
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.ExportPassphraseProblem
import app.storyarc.core.model.LibraryDocumentCoder
import app.storyarc.core.model.LibrarySecretSealer
import java.time.LocalDate
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `library-portability` tasks 2.4, 2.5 and 5.3: the export sheet, and what it hands the picker.
 * iOS's `LibraryExportSheetTests` asserts the same rows.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h800dp")
class LibraryExportSheetTest {

    @get:Rule
    val compose = createComposeRule()

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun string(id: Int) = context.getString(id)

    private fun isDrawn(text: String) =
        compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()

    private fun show(state: LibraryExportState) {
        compose.setContent {
            StoryArcTheme { LibraryExportContent(state = state, onExport = {}, onCancel = {}) }
        }
        compose.waitForIdle()
    }

    // What the sheet says.

    @Test
    fun `the sheet says what the file is not, no publication files, no downloads, no cover cache`() {
        show(LibraryExportState())

        assertTrue(isDrawn(string(R.string.transfer_export_not_what)))
        assertTrue(string(R.string.transfer_export_not_what).contains("cover cache"))
        assertTrue(isDrawn(string(R.string.transfer_export_carries)))
        assertTrue(isDrawn(string(R.string.transfer_export_readable)))
    }

    @Test
    fun `the warning sits beside the switch before the reader turns it on`() {
        show(LibraryExportState())

        assertTrue(isDrawn(string(R.string.transfer_export_passwords)))
        assertTrue(isDrawn(string(R.string.transfer_export_passwords_warning)))
    }

    @Test
    fun `the passphrase is asked for twice only when the switch is on`() {
        val state = LibraryExportState()
        show(state)
        assertFalse(isDrawn(string(R.string.transfer_passphrase)))

        compose.onNodeWithText(string(R.string.transfer_export_passwords)).performClick()
        compose.waitForIdle()

        assertTrue(state.includesPasswords)
        assertTrue(isDrawn(string(R.string.transfer_passphrase)))
        assertTrue(isDrawn(string(R.string.transfer_passphrase_again)))
        assertTrue(isDrawn(string(R.string.transfer_export_passphrase_note)))
    }

    @Test
    fun `a mismatch and an empty value are each stated`() {
        val state = LibraryExportState().apply { includesPasswords = true }
        show(state)
        assertTrue(isDrawn(string(R.string.transfer_export_problem_empty)))

        state.passphrase = "abc"
        state.confirmation = "abd"
        compose.waitForIdle()

        assertTrue(isDrawn(string(R.string.transfer_export_problem_mismatch)))
        assertFalse(isDrawn(string(R.string.transfer_export_problem_empty)))
    }

    @Test
    fun `the export button is off while the pair is wrong`() {
        val state = LibraryExportState().apply { includesPasswords = true }
        show(state)

        assertFalse(state.canExport)
        state.passphrase = "one"
        state.confirmation = "one"
        assertTrue(state.canExport)
    }

    // What it hands the picker.

    @Test
    fun `the switch is off by default and a reader who does nothing can export`() {
        val state = LibraryExportState()

        assertFalse(state.includesPasswords)
        assertNull(state.problem)
        assertTrue(state.canExport)
    }

    @Test
    fun `with the switch on an empty or mismatched pair cannot export`() = runBlocking {
        val device = TransferDevice(context)
        val state = LibraryExportState().apply { includesPasswords = true }

        assertEquals(ExportPassphraseProblem.EMPTY, state.problem)
        state.passphrase = "one"
        state.confirmation = "two"
        assertEquals(ExportPassphraseProblem.MISMATCH, state.problem)
        state.prepare(device.transfer, "10.14.0")
        assertNull(state.prepared)
    }

    @Test
    fun `the bytes the picker receives decode back to the library, with no secrets object`() = runBlocking {
        val device = TransferDevice(context).holding()
        val state = LibraryExportState()

        state.prepare(device.transfer, "10.14.0")
        val text = String(requireNotNull(state.prepared), Charsets.UTF_8)
        val document = LibraryDocumentCoder.decode(text).getOrThrow()

        assertNull(document.secrets)
        assertEquals(listOf("Comics NAS", "Kavita"), document.library.sources.map { it.displayName })
        assertEquals(listOf("Image Comics"), document.library.collections.map { it.name })
        assertFalse(text.contains("nas-password"))
    }

    @Test
    fun `with the switch on the bytes carry sealed secrets and none in clear`() = runBlocking {
        val device = TransferDevice(context).holding()
        val state = LibraryExportState().apply {
            includesPasswords = true
            passphrase = "a long phrase"
            confirmation = "a long phrase"
        }

        state.prepare(device.transfer, "10.14.0")
        val text = String(requireNotNull(state.prepared), Charsets.UTF_8)
        val block = requireNotNull(LibraryDocumentCoder.decode(text).getOrThrow().secrets)

        assertFalse(text.contains("nas-password"))
        assertFalse(text.contains("kavita-key"))
        assertFalse(text.contains("a long phrase"))
        assertEquals(2, LibrarySecretSealer.open(block, "a long phrase").size)
    }

    @Test
    fun `the passphrase leaves memory with the sheet`() {
        val state = LibraryExportState().apply {
            includesPasswords = true
            passphrase = "one"
            confirmation = "one"
        }

        state.clearSecrets()

        assertEquals("", state.passphrase)
        assertEquals("", state.confirmation)
        assertNull(state.prepared)
    }

    @Test
    fun `closing the picker lets the bytes go`() = runBlocking {
        val device = TransferDevice(context).holding()
        val state = LibraryExportState()
        state.prepare(device.transfer, "10.14.0")
        assertNotNull(state.prepared)

        state.pickerClosed()

        assertNull(state.prepared)
    }

    @Test
    fun `the picked destination receives the prepared bytes and the bytes are let go`() = runBlocking {
        val device = TransferDevice(context).holding()
        val state = LibraryExportState()
        state.prepare(device.transfer, "10.14.0")
        val prepared = requireNotNull(state.prepared)
        val destination = java.io.ByteArrayOutputStream()

        assertTrue(state.deliver { destination })

        assertTrue(prepared.contentEquals(destination.toByteArray()))
        assertNull(state.prepared)
        assertFalse(state.hasFailed)
    }

    @Test
    fun `a destination that refuses the bytes is stated on the sheet`() = runBlocking {
        val device = TransferDevice(context).holding()
        val state = LibraryExportState()
        state.prepare(device.transfer, "10.14.0")

        assertFalse(state.deliver { throw java.io.IOException("the disk is full") })

        assertTrue(state.hasFailed)
        show(state)
        assertTrue(isDrawn(string(R.string.transfer_export_failed)))
    }

    @Test
    fun `a picker closed without a choice says nothing`() = runBlocking {
        val device = TransferDevice(context).holding()
        val state = LibraryExportState()
        state.prepare(device.transfer, "10.14.0")

        assertFalse(state.deliver(null))

        assertFalse(state.hasFailed)
        assertNull(state.prepared)
    }

    @Test
    fun `the picker offers a dated name`() {
        assertEquals("StoryArc library 2026-10-08.json", ExportDestination.defaultName(LocalDate.of(2026, 10, 8)))
    }
}
