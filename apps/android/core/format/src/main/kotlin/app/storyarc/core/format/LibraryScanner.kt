package app.storyarc.core.format

import android.content.ContentResolver
import android.net.Uri
import app.storyarc.core.model.FolderSnapshot
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
    /**
     * @param skipping paths an earlier, interrupted scan of this folder already indexed.
     *   `local-library` requires a scan to be "cancellable and resumable", and this is the
     *   resumable half: the walk still visits them, which costs one directory listing, and
     *   opens none of them, which is where the minutes go.
     */
    fun scan(folder: File, skipping: Set<String> = emptySet()): Flow<ScanEvent> = flow {
        // The picked folder's own name is not a series: it is the library.
        val tally = walk(folder, seriesHint = null, skipping = skipping) { emit(it) }
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
    fun scan(
        resolver: ContentResolver,
        tree: Uri,
        skipping: Set<String> = emptySet(),
    ): Flow<ScanEvent> = flow {
        val tally = walkTree(
            resolver,
            tree,
            SafTree.rootDocumentId(tree),
            seriesHint = null,
            skipping = skipping,
        ) { emit(it) }
        emit(ScanEvent.Finished(tally.found, tally.skipped))
    }

    /**
     * What a folder holds, without opening anything in it.
     *
     * The cheap half of `local-library`'s watched changes: the app "reconciles by comparing
     * file modification times and sizes rather than re-reading every archive". A directory
     * listing is one call per folder; opening an archive is hundreds of reads, and a
     * reconcile that opened them all would be the full rescan the requirement forbids.
     *
     * The same decisions as [scan] -- the same extensions, and the same
     * a-folder-of-images-is-one-publication rule -- because the two lists are compared
     * against each other. A disagreement would make the same publication appear and
     * disappear on every pass.
     */
    fun entries(folder: File): List<FolderSnapshot.Entry> =
        buildList { list(folder, this) }

    /**
     * The same listing over a picked folder, which has no path behind it.
     *
     * Carries more than the snapshot needs. A reconcile opens only the documents that
     * changed, and it has to produce the publication a scan would have produced -- same name,
     * same series -- so the walk hands on what it knew about where each document sat. Android
     * has to be told; iOS reads the same two facts back off the path.
     */
    fun listing(resolver: ContentResolver, tree: Uri): List<Listed> =
        buildList { listTree(resolver, tree, SafTree.rootDocumentId(tree), seriesHint = null, this) }

    /** Just the snapshot's half of [listing]. */
    fun entries(resolver: ContentResolver, tree: Uri): List<FolderSnapshot.Entry> =
        listing(resolver, tree).map { it.entry }

    /**
     * One listed document, and what the walk knew about where it sits.
     *
     * @param isFolder whether the document is a folder of images, which is one publication
     *   rather than a shelf -- the same decision [scan] makes, carried so a reconcile does
     *   not have to make it again and risk making it differently.
     */
    data class Listed(
        val entry: FolderSnapshot.Entry,
        val documentId: String,
        val name: String,
        val seriesHint: String?,
        val isFolder: Boolean,
    )

    /**
     * One document, indexed exactly as a scan would index it.
     *
     * The expensive half, called only for what [FolderSnapshot.change] said had moved.
     */
    suspend fun index(
        resolver: ContentResolver,
        tree: Uri,
        listed: Listed,
    ): Publication {
        val uri = SafTree.documentUri(tree, listed.documentId)
        if (listed.isFolder) {
            return PublicationIndexer.index(
                DocumentFolderArchive.open(resolver, tree, listed.documentId),
                identityOf(uri),
                listed.name,
                listed.seriesHint,
            )
        }
        // Closed as soon as the archive is catalogued, for the reason [indexDocument] gives.
        return UriSource(resolver, uri).use { source ->
            PublicationIndexer.index(
                source = source,
                name = listed.name,
                identity = identityOf(uri),
                seriesHint = listed.seriesHint,
            )
        }
    }

    private fun list(directory: File, found: MutableList<FolderSnapshot.Entry>) {
        val children = (directory.listFiles() ?: emptyArray()).filterNot { it.name.startsWith(".") }
        val files = children.filter { it.isFile }
        val publications = files.filter { it.extension.lowercase() in CANDIDATE_EXTENSIONS }
        val images = files.filter { it.extension.lowercase() in IMAGE_EXTENSIONS }

        if (publications.isEmpty() && images.isNotEmpty()) {
            // A folder of images has no size of its own, so it is compared on its
            // modification time alone -- which is what changes when a page is added to it.
            found += FolderSnapshot.Entry(directory.absolutePath, directory.lastModified(), 0)
            return
        }
        for (file in publications) {
            found += FolderSnapshot.Entry(file.absolutePath, file.lastModified(), file.length())
        }
        for (child in children.filter { it.isDirectory }) list(child, found)
    }

    private fun listTree(
        resolver: ContentResolver,
        tree: Uri,
        documentId: String,
        seriesHint: String?,
        found: MutableList<Listed>,
    ) {
        val children = SafTree.children(resolver, tree, documentId)
            .filterNot { it.name.startsWith(".") }
        val files = children.filterNot { it.isDirectory }
        val publications = files.filter { extensionOf(it.name) in CANDIDATE_EXTENSIONS }
        val images = files.filter { extensionOf(it.name) in IMAGE_EXTENSIONS }

        if (publications.isEmpty() && images.isNotEmpty()) {
            val uri = SafTree.documentUri(tree, documentId)
            val name = uri.lastPathSegment?.substringAfterLast('/') ?: documentId
            // A folder of images has no size or time of its own that a provider will state,
            // so it is compared on nothing and re-read whenever the folder is walked. Honest
            // rather than clever: a provider that reports neither leaves nothing to compare.
            found += Listed(
                FolderSnapshot.Entry(uri.toString(), 0, 0),
                documentId,
                name,
                seriesHint,
                isFolder = true,
            )
            return
        }
        for (entry in publications) {
            found += Listed(
                FolderSnapshot.Entry(
                    // The document `Uri`, because that is what the identity of a scanned
                    // document carries and what the library keys a location on.
                    SafTree.documentUri(tree, entry.documentId).toString(),
                    entry.modifiedAtEpochMillis,
                    entry.size,
                ),
                entry.documentId,
                entry.name,
                seriesHint,
                isFolder = false,
            )
        }
        for (child in children.filter { it.isDirectory }) {
            listTree(resolver, tree, child.documentId, child.name, found)
        }
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
        skipping: Set<String>,
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
            if (directory.absolutePath in skipping) return Tally()
            return index(directory, seriesHint, emit)
        }

        var tally = Tally()
        for (file in publicationFiles) {
            currentCoroutineContext().ensureActive()
            // Already done by the scan this one is picking up from. Not counted either: the
            // caller put those publications back itself and has already counted them.
            if (file.absolutePath in skipping) continue
            tally += index(file, seriesHint, emit)
        }
        for (child in directories) {
            currentCoroutineContext().ensureActive()
            tally += walk(child, child.name, skipping, emit)
        }
        return tally
    }

    private suspend fun walkTree(
        resolver: ContentResolver,
        tree: Uri,
        documentId: String,
        seriesHint: String?,
        skipping: Set<String>,
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
            val folder = SafTree.documentUri(tree, documentId).toString()
            if (folder in skipping) return Tally()
            return indexDocumentFolder(resolver, tree, documentId, seriesHint, emit)
        }

        var tally = Tally()
        for (entry in publications) {
            currentCoroutineContext().ensureActive()
            // Already done by the scan this one is picking up from, and identified the way
            // the library identifies a document: by the `Uri` its identity carries.
            if (SafTree.documentUri(tree, entry.documentId).toString() in skipping) continue
            tally += indexDocument(resolver, tree, entry, seriesHint, emit)
        }
        for (child in directories) {
            currentCoroutineContext().ensureActive()
            tally += walkTree(resolver, tree, child.documentId, child.name, skipping, emit)
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
