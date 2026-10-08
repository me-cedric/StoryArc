package app.storyarc.feature.settings

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.storyarc.core.model.LibraryDocumentCoder
import app.storyarc.core.model.LibraryDocumentFailure
import app.storyarc.core.model.LibraryDocumentRefusal
import app.storyarc.core.persistence.LibraryImportException
import app.storyarc.core.persistence.LibraryImportOutcome
import app.storyarc.core.persistence.LibraryImportPreview
import app.storyarc.core.persistence.LibraryTransfer
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A file the reader picked, as much of it as the import needs to know before it reads. */
internal interface PickedFile {
    /** The size the provider reports, or null where it reports none. */
    fun size(): Long?

    /** The file's bytes, or null where it cannot be opened. */
    fun open(): InputStream?
}

/** Why the import screen shows a refusal instead of a preview. */
internal sealed interface ImportRefusal {
    /** The document was read and refused, by name. */
    data class Document(val failure: LibraryDocumentFailure) : ImportRefusal

    /** The file could not be opened or read at all. */
    data object Unopened : ImportRefusal
}

/** Where the import flow stands. */
internal sealed interface ImportPhase {
    data object Idle : ImportPhase

    data object Reading : ImportPhase

    data class Preview(val preview: LibraryImportPreview) : ImportPhase

    data class Refused(val refusal: ImportRefusal) : ImportPhase

    data object Importing : ImportPhase

    data class Done(val outcome: LibraryImportOutcome) : ImportPhase

    data object Failed : ImportPhase
}

/**
 * The import flow, from the file the reader picked to what the import did.
 *
 * `library-portability` / *The reader sees what will happen first*. Reading a file plans the
 * import and changes nothing; only [confirm] does. A file over the size limit is refused from
 * the size the provider reports, before a byte of it is read (task 6.5), and one that reports
 * no size is read only as far as the limit allows. iOS's `LibraryImportModel` is the same flow.
 */
internal class LibraryImportState {
    var phase by mutableStateOf<ImportPhase>(ImportPhase.Idle)
        private set

    /** What the reader typed for the sealed passwords. Cleared when the import ends. */
    var passphrase by mutableStateOf("")

    /** The last passphrase did not open the passwords. The reader may try again. */
    var passphraseRefused by mutableStateOf(false)
        private set

    val isBusy: Boolean get() = phase == ImportPhase.Reading || phase == ImportPhase.Importing

    /** The picker returned nothing readable. */
    fun markUnopened() {
        phase = ImportPhase.Refused(ImportRefusal.Unopened)
    }

    /** Reads the picked file and plans the import. Changes nothing on the device. */
    suspend fun load(file: PickedFile, transfer: LibraryTransfer) {
        phase = ImportPhase.Reading
        passphrase = ""
        passphraseRefused = false
        phase = try {
            val text = withContext(Dispatchers.IO) { readWithinLimit(file) }
            ImportPhase.Preview(transfer.preview(text))
        } catch (refusal: LibraryDocumentRefusal) {
            ImportPhase.Refused(ImportRefusal.Document(refusal.reason))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            // A provider can throw any of the exceptions a binder call carries, not only an
            // IOException. Each one is a file that could not be read, never a crash.
            ImportPhase.Refused(ImportRefusal.Unopened)
        }
    }

    /**
     * Merges the document into the library.
     *
     * @param skippingSecrets import everything but the passwords; those libraries ask for a
     *   sign-in.
     */
    suspend fun confirm(
        transfer: LibraryTransfer,
        skippingSecrets: Boolean,
        onImported: (LibraryImportOutcome) -> Unit,
    ) {
        val preview = (phase as? ImportPhase.Preview)?.preview ?: return
        phase = ImportPhase.Importing
        phase = try {
            val outcome = transfer.performImport(preview, if (skippingSecrets) null else passphrase)
            passphrase = ""
            onImported(outcome)
            ImportPhase.Done(outcome)
        } catch (failure: LibraryImportException) {
            passphraseRefused = true
            ImportPhase.Preview(preview)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            passphrase = ""
            ImportPhase.Failed
        }
    }

    /** The sheet closed. Nothing of the file or the passphrase stays. */
    fun reset() {
        passphrase = ""
        passphraseRefused = false
        phase = ImportPhase.Idle
    }

    /**
     * The file's text, refused before it is read when the provider reports a size over the limit.
     *
     * @throws LibraryDocumentRefusal when the file is too large.
     */
    private fun readWithinLimit(file: PickedFile): String {
        file.size()?.let { size ->
            LibraryDocumentCoder.admits(size)?.let { throw LibraryDocumentRefusal(it) }
        }
        val stream = file.open() ?: throw IOException("the file could not be opened")
        val limit = LibraryDocumentCoder.MAXIMUM_BYTES
        val bytes = stream.use { readAtMost(it, limit + 1) }
        LibraryDocumentCoder.admits(bytes.size.toLong())?.let { throw LibraryDocumentRefusal(it) }
        return bytes.toString(Charsets.UTF_8)
    }

    private fun readAtMost(stream: InputStream, count: Long): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        var remaining = count
        while (remaining > 0) {
            val read = stream.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            if (read < 0) break
            out.write(buffer, 0, read)
            remaining -= read
        }
        return out.toByteArray()
    }
}
