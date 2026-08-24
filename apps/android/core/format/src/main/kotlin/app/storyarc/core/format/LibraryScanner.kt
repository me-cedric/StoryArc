package app.storyarc.core.format

import app.storyarc.core.model.Publication
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.toList
import java.io.File

/**
 * What a scan reports as it goes.
 *
 * `local-library` requires a scan to report progress as a count of items found and
 * not to block browsing what it has already found — so it emits as it walks rather
 * than returning a list at the end.
 */
sealed interface ScanEvent {
    /**
     * A publication was indexed. Emitted the moment it is known, so the first
     * screen can fill while the rest of the folder is still being walked.
     */
    data class Found(val publication: Publication) : ScanEvent

    /**
     * A file was recognised and not indexed. Carries a reason the library can show,
     * because `publication-formats` forbids a silent failure.
     */
    data class Skipped(val path: String, val reason: String) : ScanEvent

    /** The walk finished. */
    data class Finished(val found: Int, val skipped: Int) : ScanEvent
}

/**
 * Walks a folder and turns what it finds into publications.
 *
 * `local-library`: "walks it recursively, identifies supported publications,
 * extracts covers and metadata, and reports progress as a count of items found",
 * cancellable, resumable, and never blocking the browsing of what is already
 * found.
 *
 * A [Flow] delivers all four at once. Cancelling the collecting coroutine stops the
 * walk; the events already delivered are the resumable state; and nothing waits for
 * the whole folder before the first row appears. iOS's `LibraryScanner` uses an
 * `AsyncStream` for the same reasons.
 */
object LibraryScanner {
    /**
     * Extensions worth opening. A cheap pre-filter, not the decision — format is
     * still determined from content, so a `.cbz` that is really a RAR opens as a
     * RAR. This only avoids opening every text file in a folder.
     */
    private val CANDIDATE_EXTENSIONS =
        setOf("cbz", "cbr", "cb7", "cbt", "epub", "pdf", "zip", "rar")

    private val IMAGE_EXTENSIONS =
        setOf("jpg", "jpeg", "png", "gif", "webp", "avif", "heic", "bmp", "tif", "tiff")

    /**
     * Publications in [folder], emitted as they are found.
     *
     * Depth-first and alphabetical, so the order a user sees matches the order they
     * would see in a file browser — a scan that returns rows in filesystem order
     * looks broken even when it is complete.
     */
    fun scan(folder: File): Flow<ScanEvent> = flow {
        val tally = walk(folder) { emit(it) }
        emit(ScanEvent.Finished(tally.found, tally.skipped))
    }

    /**
     * Everything in a folder, for a caller that genuinely wants the whole list.
     *
     * The indexer for a small folder, or a test. A library UI should collect the
     * flow instead — this waits for the last file before returning the first.
     */
    suspend fun scanAll(folder: File): List<Publication> =
        scan(folder).mapNotNull { (it as? ScanEvent.Found)?.publication }.toList()

    /**
     * How much a walk found, so counts add up across recursion without shared
     * mutable state.
     */
    private data class Tally(val found: Int = 0, val skipped: Int = 0) {
        operator fun plus(other: Tally) = Tally(found + other.found, skipped + other.skipped)
    }

    private suspend fun walk(directory: File, emit: suspend (ScanEvent) -> Unit): Tally {
        currentCoroutineContext().ensureActive()
        // Alphabetical, case-insensitively, so the order matches a file browser's.
        val children = (directory.listFiles() ?: emptyArray())
            .filterNot { it.name.startsWith(".") }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })

        val directories = children.filter { it.isDirectory }
        val files = children.filter { it.isFile }
        val publicationFiles = files.filter { it.extension.lowercase() in CANDIDATE_EXTENSIONS }
        val imageFiles = files.filter { it.extension.lowercase() in IMAGE_EXTENSIONS }

        // A directory holding images and no publications is itself one publication.
        // A directory holding publications is a shelf. Deciding per directory is
        // what lets an unpacked comic sit next to packed ones without either being
        // mistaken for the other.
        if (publicationFiles.isEmpty() && imageFiles.isNotEmpty()) {
            // Its subdirectories are chapters of it, not separate publications.
            return index(directory, emit)
        }

        var tally = Tally()
        for (file in publicationFiles) {
            currentCoroutineContext().ensureActive()
            tally += index(file, emit)
        }
        for (child in directories) {
            currentCoroutineContext().ensureActive()
            tally += walk(child, emit)
        }
        return tally
    }

    /**
     * Indexes one entry and emits the result.
     *
     * The `emit` is deliberately **outside** the `try`. A broad catch wrapped
     * around an emission swallows `AbortFlowException`, which is how a downstream
     * `take` or `first` cancels — the collector would appear to cancel and the scan
     * would carry on, reporting the cancellation itself as a skipped file.
     * `CancellationException` is re-thrown for the same reason.
     */
    private suspend fun index(file: File, emit: suspend (ScanEvent) -> Unit): Tally {
        val event = try {
            ScanEvent.Found(PublicationIndexer.index(file))
        } catch (cause: IndexException) {
            ScanEvent.Skipped(file.name, reasonFor(cause))
        } catch (cause: CancellationException) {
            throw cause
        } catch (_: Exception) {
            ScanEvent.Skipped(file.name, "it could not be read")
        }
        emit(event)
        return if (event is ScanEvent.Found) Tally(found = 1) else Tally(skipped = 1)
    }

    /**
     * A reason in words a person can act on.
     *
     * "7-Zip is not supported" tells someone to convert the file; "could not open"
     * tells them nothing, which is what `publication-formats` forbids.
     */
    private fun reasonFor(cause: IndexException): String = when (cause) {
        is IndexException.Unsupported -> "${cause.format} is not a format StoryArc reads"
        is IndexException.Unreadable -> cause.reason
    }
}
