package app.storyarc.core.format

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract

/**
 * An unpacked comic inside a folder the user picked through the Storage Access
 * Framework.
 *
 * The same publication [ImageFolderArchive] describes, reached the only way a
 * content provider allows. Pages are the documents enumerated when the archive was
 * opened, so a path can never escape the folder — there is no path to construct,
 * only a `Uri` that was already listed.
 */
class DocumentFolderArchive private constructor(
    private val resolver: ContentResolver,
    private val pageUris: Map<String, Uri>,
    override val pages: List<PageEntry>,
    override val skippedPageCount: Int,
    val comicInfoData: ByteArray?,
) : ComicArchiveReading {

    val comicInfo: ComicInfo? by lazy { comicInfoData?.let(ComicInfo::parse) }

    override val coverPage: PageEntry?
        get() = CoverSelection.cover(pages, comicInfo?.coverPageIndex)

    companion object {
        /** Opens the folder [documentId] names, walking its subfolders as chapters. */
        fun open(resolver: ContentResolver, tree: Uri, documentId: String): DocumentFolderArchive {
            val candidates = mutableListOf<PageEntry>()
            val uris = mutableMapOf<String, Uri>()
            var skipped = 0
            var comicInfo: Uri? = null

            fun walk(id: String, prefix: String) {
                for (entry in SafTree.children(resolver, tree, id)) {
                    val path = if (prefix.isEmpty()) entry.name else "$prefix/${entry.name}"
                    if (entry.isDirectory) {
                        walk(entry.documentId, path)
                        continue
                    }
                    if (path.lowercase().endsWith("comicinfo.xml")) {
                        comicInfo = SafTree.documentUri(tree, entry.documentId)
                        continue
                    }
                    if (!PageOrdering.isPage(path)) continue
                    if (entry.size == 0L) {
                        skipped++
                        continue
                    }
                    candidates += PageEntry(path, entry.size)
                    uris[path] = SafTree.documentUri(tree, entry.documentId)
                }
            }
            walk(documentId, "")

            return DocumentFolderArchive(
                resolver = resolver,
                pageUris = uris,
                pages = PageOrdering.sorted(candidates),
                skippedPageCount = skipped,
                comicInfoData = comicInfo?.let { read(resolver, it) },
            )
        }

        /**
         * Opens the folder a document `Uri` points at.
         *
         * A `Uri` built from a tree carries the tree in its own path, so the
         * children query can be built from it without the caller having to keep
         * the original tree `Uri` beside it.
         */
        fun open(resolver: ContentResolver, documentUri: Uri): DocumentFolderArchive =
            open(resolver, documentUri, DocumentsContract.getDocumentId(documentUri))

        private fun read(resolver: ContentResolver, uri: Uri): ByteArray? =
            runCatching { resolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()
    }

    override suspend fun data(page: PageEntry): ByteArray {
        val uri = pageUris[page.path] ?: throw ComicArchiveException.Unreadable()
        return read(resolver, uri) ?: throw ComicArchiveException.Unreadable()
    }

    /** Nothing to close: each page is opened and closed as it is read. */
    override fun close() = Unit
}
