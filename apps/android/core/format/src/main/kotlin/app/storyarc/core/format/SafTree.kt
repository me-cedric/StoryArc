package app.storyarc.core.format

import android.content.ContentResolver
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract

/**
 * A folder the user picked through the Storage Access Framework.
 *
 * Android does not hand an app a path. A picked folder arrives as a tree `Uri`,
 * and everything inside it is reached by asking a `ContentProvider` — so the
 * `File`-based walk in [LibraryScanner] cannot see a single byte of it. This is
 * the smallest thing that makes the walk possible: list a directory, and turn a
 * document id into a `Uri`.
 *
 * ponytail: [DocumentsContract] directly rather than `androidx.documentfile`.
 * `DocumentFile.listFiles()` runs one provider query per child and then one more
 * for each name, size and type asked of it; one cursor with a projection answers
 * all of it for a whole directory. On a folder of 2,000 comics that is the
 * difference between a scan and a hang, and it costs no dependency.
 */
object SafTree {

    /** One entry in a picked folder. */
    data class Entry(
        val documentId: String,
        val name: String,
        val isDirectory: Boolean,
        val size: Long,
        /**
         * When the provider says it last changed, or 0 when it does not say.
         *
         * Asked for in the same cursor as the rest, because `local-library` reconciles a
         * watched folder "by comparing file modification times and sizes" and a second query
         * per file would cost more than the archive read it is there to avoid.
         */
        val modifiedAtEpochMillis: Long = 0,
    )

    private val PROJECTION = arrayOf(
        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        DocumentsContract.Document.COLUMN_MIME_TYPE,
        DocumentsContract.Document.COLUMN_SIZE,
        DocumentsContract.Document.COLUMN_LAST_MODIFIED,
    )

    /**
     * Folders the user picked in an earlier session.
     *
     * `local-library` requires a picked folder to be reachable "after a device
     * restart without asking again". Android already does that: a tree `Uri` the
     * app took a persistable permission on comes back from the system across
     * restarts. So there is nothing to store — iOS needs security-scoped bookmarks
     * in its own defaults, and this is the platform's own version of the same
     * thing.
     */
    fun persistedTrees(resolver: ContentResolver): List<Uri> =
        resolver.persistedUriPermissions
            .filter { it.isReadPermission }
            .sortedBy { it.persistedTime }
            .map { it.uri }

    /**
     * A folder's name as the provider states it, or `null` when it is gone.
     *
     * Doubles as the reachability check. `local-library` requires an unreachable
     * folder to be named and offered a single re-pick, and a name is what makes
     * that notice worth reading.
     */
    fun displayName(resolver: ContentResolver, tree: Uri): String? {
        val document = runCatching { documentUri(tree, rootDocumentId(tree)) }.getOrNull()
            ?: return null
        return column(resolver, document, DocumentsContract.Document.COLUMN_DISPLAY_NAME)
    }

    /**
     * One string column of one document, or `null`.
     *
     * A provider answers only the columns it knows. Asking for a column it does not
     * have yields a cursor with no columns at all rather than a null value, so the
     * index is looked up by name every time — reading position 0 blind is a crash
     * on any provider that is not `DocumentsProvider`.
     */
    private fun column(resolver: ContentResolver, uri: Uri, name: String): String? {
        val cursor = runCatching {
            resolver.query(uri, arrayOf(name), null, null, null)
        }.getOrNull() ?: return null
        return cursor.use {
            if (!it.moveToFirst()) return@use null
            val index = it.getColumnIndex(name)
            if (index < 0 || it.isNull(index)) null else it.getString(index)
        }
    }

    /** The document id of the folder itself. */
    fun rootDocumentId(tree: Uri): String = DocumentsContract.getTreeDocumentId(tree)

    /** The `Uri` for one document inside [tree], which is what opens its bytes. */
    fun documentUri(tree: Uri, documentId: String): Uri =
        DocumentsContract.buildDocumentUriUsingTree(tree, documentId)

    /**
     * Whether a document is a folder.
     *
     * One column of one row. Asked before opening a document, because a folder of
     * images is a publication and a file is a different one.
     */
    fun isDirectory(resolver: ContentResolver, uri: Uri): Boolean =
        column(resolver, uri, DocumentsContract.Document.COLUMN_MIME_TYPE) ==
            DocumentsContract.Document.MIME_TYPE_DIR

    /**
     * What is directly inside a directory.
     *
     * Empty when the provider refuses the query — a folder whose permission was
     * revoked reads as empty rather than throwing, and the caller reports the scan
     * as finding nothing rather than crashing on a folder the user removed from
     * their device.
     */
    fun children(resolver: ContentResolver, tree: Uri, documentId: String): List<Entry> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
        val cursor: Cursor = runCatching {
            resolver.query(childrenUri, PROJECTION, null, null, null)
        }.getOrNull() ?: return emptyList()

        return cursor.use {
            // By name, not by position: a provider is free to return fewer columns
            // than were asked for, and a fixed index then reads the wrong one or
            // throws.
            val idColumn = it.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameColumn = it.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeColumn = it.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeColumn = it.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modifiedColumn =
                it.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            if (idColumn < 0 || nameColumn < 0) return@use emptyList()

            buildList {
                while (it.moveToNext()) {
                    val id = it.getString(idColumn) ?: continue
                    val name = it.getString(nameColumn) ?: continue
                    val mime = if (mimeColumn < 0) null else it.getString(mimeColumn)
                    add(
                        Entry(
                            documentId = id,
                            name = name,
                            isDirectory = mime == DocumentsContract.Document.MIME_TYPE_DIR,
                            // -1 means "the provider did not say", which is not the
                            // same as an empty file and must not be skipped as one.
                            size = if (sizeColumn < 0 || it.isNull(sizeColumn)) {
                                -1L
                            } else {
                                it.getLong(sizeColumn)
                            },
                            // 0 rather than -1: a provider that does not say gets compared
                            // on its size alone, which is the honest half of the answer.
                            modifiedAtEpochMillis =
                                if (modifiedColumn < 0 || it.isNull(modifiedColumn)) {
                                    0L
                                } else {
                                    it.getLong(modifiedColumn)
                                },
                        ),
                    )
                }
            }
        }
    }
}
