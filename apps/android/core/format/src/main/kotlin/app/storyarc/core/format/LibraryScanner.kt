package app.storyarc.core.format

import android.content.ContentResolver
import android.net.Uri
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationIdentity
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
        // The picked folder's own name is not a series: it is the library.
        val tally = walk(folder, seriesHint = null) { emit(it) }
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
     * Publications in a folder the user picked, emitted as they are found.
     *
     * The same walk, over a content provider. Android hands a picked folder over as
     * a tree `Uri` with no path behind it, so `local-library`'s "the user picks a
     * folder" is only reachable this way — the `File` overload above serves the
     * app's own storage and the tests.
     *
     * The rules are identical on purpose: same extensions, same alphabetical order,
     * same image-folder-is-a-publication decision. A user who moves a shelf from
     * internal storage to an SD card should see the same library.
     */
    fun scan(resolver: ContentResolver, tree: Uri): Flow<ScanEvent> = flow {
        val tally = walkTree(resolver, tree, SafTree.rootDocumentId(tree), seriesHint = null) {
            emit(it)
        }
        emit(ScanEvent.Finished(tally.found, tally.skipped))
    }

    /**
     * How much a walk found, so counts add up across recursion without shared
     * mutable state.
     */
    private data class Tally(val found: Int = 0, val skipped: Int = 0) {
        operator fun plus(other: Tally) = Tally(found + other.found, skipped + other.skipped)
    }

    /**
     * @param seriesHint what to call the series when a publication's own name does
     *   not say. `local-library` presents a subfolder of a library "as a series
     *   whose name is the folder name"; passing the name down is the metadata half
     *   of that, and it is why the top-level call passes `null` — the library's own
     *   folder is not a series.
     */
    private suspend fun walk(
        directory: File,
        seriesHint: String?,
        emit: suspend (ScanEvent) -> Unit,
    ): Tally {
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
            return index(directory, seriesHint, emit)
        }

        var tally = Tally()
        for (file in publicationFiles) {
            currentCoroutineContext().ensureActive()
            tally += index(file, seriesHint, emit)
        }
        for (child in directories) {
            currentCoroutineContext().ensureActive()
            tally += walk(child, child.name, emit)
        }
        return tally
    }

    private suspend fun walkTree(
        resolver: ContentResolver,
        tree: Uri,
        documentId: String,
        seriesHint: String?,
        emit: suspend (ScanEvent) -> Unit,
    ): Tally {
        currentCoroutineContext().ensureActive()
        val children = SafTree.children(resolver, tree, documentId)
            .filterNot { it.name.startsWith(".") }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })

        val directories = children.filter { it.isDirectory }
        val files = children.filterNot { it.isDirectory }
        val publications = files.filter { extensionOf(it.name) in CANDIDATE_EXTENSIONS }
        val images = files.filter { extensionOf(it.name) in IMAGE_EXTENSIONS }

        if (publications.isEmpty() && images.isNotEmpty()) {
            return indexDocumentFolder(resolver, tree, documentId, seriesHint, emit)
        }

        var tally = Tally()
        for (entry in publications) {
            currentCoroutineContext().ensureActive()
            tally += indexDocument(resolver, tree, entry, seriesHint, emit)
        }
        for (child in directories) {
            currentCoroutineContext().ensureActive()
            tally += walkTree(resolver, tree, child.documentId, child.name, emit)
        }
        return tally
    }

    private fun extensionOf(name: String): String = name.substringAfterLast('.', "").lowercase()

    /**
     * The identity of a document.
     *
     * The document `Uri` stands in for the path. It survives a restart because the
     * tree permission does (`local-library`), and [PublicationIdentity.matches]
     * still merges it with a content digest when the background pass that computes
     * one arrives — the same trade recorded in [PublicationIndexer.identityFor].
     */
    private fun identityOf(uri: Uri) = PublicationIdentity(normalizedPath = uri.toString())

    private suspend fun indexDocument(
        resolver: ContentResolver,
        tree: Uri,
        entry: SafTree.Entry,
        seriesHint: String?,
        emit: suspend (ScanEvent) -> Unit,
    ): Tally {
        val uri = SafTree.documentUri(tree, entry.documentId)
        val event = try {
            // Closed as soon as the archive is catalogued: a scan of 2,000 files
            // holding 2,000 open descriptors exhausts the process limit long
            // before it finishes. The reader opens its own when a page is asked
            // for.
            UriSource(resolver, uri).use { source ->
                ScanEvent.Found(
                    PublicationIndexer.index(
                        source = source,
                        name = entry.name,
                        identity = identityOf(uri),
                        seriesHint = seriesHint,
                    ),
                )
            }
        } catch (cause: IndexException) {
            ScanEvent.Skipped(entry.name, reasonFor(cause))
        } catch (cause: CancellationException) {
            throw cause
        } catch (_: Exception) {
            ScanEvent.Skipped(entry.name, "it could not be read")
        }
        emit(event)
        return if (event is ScanEvent.Found) Tally(found = 1) else Tally(skipped = 1)
    }

    private suspend fun indexDocumentFolder(
        resolver: ContentResolver,
        tree: Uri,
        documentId: String,
        seriesHint: String?,
        emit: suspend (ScanEvent) -> Unit,
    ): Tally {
        val uri = SafTree.documentUri(tree, documentId)
        val name = uri.lastPathSegment?.substringAfterLast('/') ?: documentId
        val event = try {
            ScanEvent.Found(
                PublicationIndexer.index(
                    DocumentFolderArchive.open(resolver, tree, documentId),
                    identityOf(uri),
                    name,
                    seriesHint,
                ),
            )
        } catch (cause: IndexException) {
            ScanEvent.Skipped(name, reasonFor(cause))
        } catch (cause: CancellationException) {
            throw cause
        } catch (_: Exception) {
            ScanEvent.Skipped(name, "it could not be read")
        }
        emit(event)
        return if (event is ScanEvent.Found) Tally(found = 1) else Tally(skipped = 1)
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
    private suspend fun index(
        file: File,
        seriesHint: String?,
        emit: suspend (ScanEvent) -> Unit,
    ): Tally {
        val event = try {
            ScanEvent.Found(PublicationIndexer.index(file, seriesHint))
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
