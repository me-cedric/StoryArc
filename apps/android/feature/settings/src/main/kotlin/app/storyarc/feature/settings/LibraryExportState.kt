package app.storyarc.feature.settings

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.storyarc.core.model.ExportPassphrase
import app.storyarc.core.model.ExportPassphraseProblem
import app.storyarc.core.persistence.LibraryTransfer
import java.io.IOException
import java.io.OutputStream
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * What the export sheet holds while the reader decides.
 *
 * `library-portability` / *Secrets travel only sealed, and only when asked*: the switch starts
 * off, and the passphrase pair is checked by the one rule both platforms share. The passphrase
 * is read to seal and kept in memory only while the sheet is open; [clearSecrets] lets it go. It
 * is written nowhere. iOS's `LibraryExportModel` is the same state.
 */
internal class LibraryExportState {
    /** Off by default: a reader who does nothing writes no secret. */
    var includesPasswords by mutableStateOf(false)
    var passphrase by mutableStateOf("")
    var confirmation by mutableStateOf("")

    var isWorking by mutableStateOf(false)
        private set
    var hasFailed by mutableStateOf(false)
        private set

    /** The prepared file, once there is one. Setting it is what offers the picker. */
    var prepared by mutableStateOf<ByteArray?>(null)
        private set

    /** What is wrong with the pair, or null. Always null while the switch is off. */
    val problem: ExportPassphraseProblem?
        get() = if (includesPasswords) ExportPassphrase.problem(passphrase, confirmation) else null

    val canExport: Boolean get() = !isWorking && problem == null

    /** Reads the library, seals what was asked for, and holds the bytes for the picker. */
    suspend fun prepare(transfer: LibraryTransfer, appVersion: String) {
        if (!canExport) return
        isWorking = true
        hasFailed = false
        try {
            prepared = transfer
                .exportText(appVersion, passphrase.takeIf { includesPasswords })
                .toByteArray(Charsets.UTF_8)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            hasFailed = true
        } finally {
            isWorking = false
        }
    }

    /** The picker closed, with a file written or without. The bytes are let go either way. */
    fun pickerClosed() {
        prepared = null
    }

    /**
     * Writes the prepared bytes to what the picker returned, off the main thread, and lets them go.
     *
     * A destination that was picked and then refused the bytes is stated on the sheet. A picker
     * closed without a choice says nothing.
     *
     * @param open opens the picked destination, or null when the reader picked none.
     * @return whether the bytes were written.
     */
    suspend fun deliver(open: (() -> OutputStream?)?): Boolean {
        val bytes = prepared ?: return false
        pickerClosed()
        if (open == null) return false
        val written = withContext(Dispatchers.IO) { ExportDestination.deliver(bytes, open) }
        hasFailed = !written
        return written
    }

    /** The passphrase leaves memory when the sheet does. */
    fun clearSecrets() {
        passphrase = ""
        confirmation = ""
        prepared = null
    }
}

/** Where the prepared bytes go: only to what the reader picked. */
internal object ExportDestination {

    /**
     * Writes [bytes] to the destination the reader picked, and to nowhere else.
     *
     * `library-portability` / *The export goes somewhere the reader picked*: the app writes no
     * file of its own. A reader who closes the picker without choosing passes no destination,
     * and nothing is opened.
     *
     * @param open opens the picked destination, or null when the reader picked none.
     * @return whether the bytes were written.
     */
    fun deliver(bytes: ByteArray, open: (() -> OutputStream?)?): Boolean {
        if (open == null) return false
        return try {
            val stream = open() ?: return false
            stream.use { it.write(bytes) }
            true
        } catch (_: IOException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    /** The name the picker offers, dated so two exports do not overwrite each other. */
    fun defaultName(on: LocalDate): String = "StoryArc library $on.json"
}
