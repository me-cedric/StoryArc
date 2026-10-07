package app.storyarc.core.format

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import java.io.File
import java.io.FileNotFoundException

/**
 * A document tree served from a directory, for tests that need a real Storage Access Framework
 * provider on the other end.
 *
 * `LibraryScanner` reaches a picked folder only through `DocumentsContract` queries, so nothing
 * about the content-tree walk can be exercised without one. [FileProvider][androidx.core.content.FileProvider]
 * answers a single file and has no notion of a folder, which is why the single-file tests could
 * stop there and this one could not.
 *
 * A document id is the path from [base], with `root` standing for [base] itself. The provider
 * answers only what the scanner asks: one document, a folder's children, and a file's bytes.
 */
class TestTreeProvider : DocumentsProvider() {

    override fun onCreate(): Boolean = true

    override fun queryRoots(projection: Array<out String>?): Cursor =
        MatrixCursor(projection ?: arrayOf(Root.COLUMN_ROOT_ID))

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor =
        MatrixCursor(projection ?: DEFAULT_PROJECTION).also { row(it, documentId) }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor = MatrixCursor(projection ?: DEFAULT_PROJECTION).also { cursor ->
        file(parentDocumentId).listFiles().orEmpty().sortedBy { it.name }
            .forEach { row(cursor, "$parentDocumentId/${it.name}") }
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor =
        ParcelFileDescriptor.open(file(documentId), ParcelFileDescriptor.parseMode(mode))

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean =
        documentId == parentDocumentId || documentId.startsWith("$parentDocumentId/")

    private fun file(documentId: String): File {
        if (!documentId.startsWith(ROOT)) throw FileNotFoundException(documentId)
        return File(base, documentId.removePrefix(ROOT).trimStart('/'))
    }

    private fun row(cursor: MatrixCursor, documentId: String) {
        val file = file(documentId)
        if (!file.exists()) throw FileNotFoundException(documentId)
        cursor.newRow()
            .add(Document.COLUMN_DOCUMENT_ID, documentId)
            .add(Document.COLUMN_DISPLAY_NAME, file.name)
            .add(
                Document.COLUMN_MIME_TYPE,
                if (file.isDirectory) Document.MIME_TYPE_DIR else "application/octet-stream",
            )
            .add(Document.COLUMN_SIZE, if (file.isDirectory) null else file.length())
            .add(Document.COLUMN_LAST_MODIFIED, file.lastModified())
            .add(Document.COLUMN_FLAGS, 0)
    }

    companion object {
        const val AUTHORITY = "app.storyarc.core.format.testtree"
        const val ROOT = "root"

        /** The directory the tree is served from. A test sets it before it asks for the tree. */
        @Volatile
        var base: File = File("/nonexistent")

        private val DEFAULT_PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
        )
    }
}
