package app.storyarc.core.persistence

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import app.storyarc.core.model.SyncFile
import app.storyarc.core.model.SyncPlace
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The sync document's place in a folder the reader picked through the system picker.
 *
 * `library-sync` task 2.3. The folder is a tree `Uri` with a persisted read and write grant, the
 * same grant `local-library` takes for a picked folder, so it survives a restart with nothing
 * stored but the `Uri`. A folder on Google Drive or another provider is written as any folder
 * is: the provider syncs the file, and the app holds no account with it.
 *
 * Each call throws when the folder cannot be reached: removed, the grant revoked, or the
 * provider refusing. The caller shows the place as unreachable. iOS's `FolderSyncPlace` is the
 * same place.
 */
class FolderSyncPlace(private val resolver: ContentResolver, private val tree: Uri) : SyncPlace {

    private class Child(val id: String, val name: String, val isDirectory: Boolean, val version: String)

    override suspend fun names(): List<String> = withContext(Dispatchers.IO) {
        children().filterNot { it.isDirectory }.map { it.name }
    }

    override suspend fun read(name: String): SyncFile? = withContext(Dispatchers.IO) {
        val child = file(name) ?: return@withContext null
        val bytes = resolver.openInputStream(documentUri(child.id))?.use { it.readBytes() }
            ?: throw IOException("the provider gave no stream")
        SyncFile(bytes.decodeToString(), child.version)
    }

    /**
     * Writes over the file in place, or makes it. A provider offers no rename with replace that
     * every provider honours, so the check and the write are two steps here. The engine reads
     * again at each sync, so a write from another device between them comes back then, and a
     * provider that keeps both makes a conflicted copy the engine merges.
     */
    override suspend fun write(name: String, text: String, replacing: String?): Boolean = withContext(Dispatchers.IO) {
        val child = file(name)
        if (child?.version != replacing) return@withContext false
        val target = child?.let { documentUri(it.id) }
            ?: DocumentsContract.createDocument(resolver, documentUri(rootId()), MIME_TYPE, name)
            ?: throw IOException("the provider made no file")
        resolver.openOutputStream(target, "wt")?.use { it.write(text.encodeToByteArray()) }
            ?: throw IOException("the provider gave no stream")
        true
    }

    override suspend fun delete(name: String): Boolean = withContext(Dispatchers.IO) {
        file(name)?.let { DocumentsContract.deleteDocument(resolver, documentUri(it.id)) }
        file(name) == null
    }

    private fun file(name: String): Child? = children().firstOrNull { it.name == name && !it.isDirectory }

    /** What is directly in the folder. A folder that has gone throws rather than reading as empty. */
    private fun children(): List<Child> {
        val listing = DocumentsContract.buildChildDocumentsUriUsingTree(tree, rootId())
        // The query with a `Bundle`: a `DocumentsProvider` refuses the older form with a selection.
        val cursor = resolver.query(listing, PROJECTION, null, null)
            ?: throw IOException("the folder cannot be read")
        return cursor.use {
            buildList {
                while (it.moveToNext()) {
                    val modified = if (it.isNull(3)) 0L else it.getLong(3)
                    val size = if (it.isNull(4)) 0L else it.getLong(4)
                    add(
                        Child(
                            id = it.getString(0),
                            name = it.getString(1),
                            isDirectory = it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR,
                            version = "$modified-$size",
                        ),
                    )
                }
            }
        }
    }

    private fun rootId(): String = DocumentsContract.getTreeDocumentId(tree)

    private fun documentUri(id: String): Uri = DocumentsContract.buildDocumentUriUsingTree(tree, id)

    private companion object {
        const val MIME_TYPE = "application/json"

        val PROJECTION = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_SIZE,
        )
    }
}
