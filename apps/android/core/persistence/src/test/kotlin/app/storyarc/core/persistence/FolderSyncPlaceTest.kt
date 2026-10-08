package app.storyarc.core.persistence

import android.content.pm.ProviderInfo
import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.DocumentsProvider
import java.io.File
import kotlin.io.path.createTempDirectory
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * `library-sync` task 2.3 through a real `DocumentsProvider`: the picked folder is written, read
 * and listed through the Storage Access Framework, the place is held across a relaunch, and a
 * removed folder throws, which the runner shows as unreachable.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FolderSyncPlaceTest {

    /** A provider over a temporary directory. A document id is the path below that directory. */
    class TestDocuments : DocumentsProvider() {
        override fun onCreate() = true

        override fun queryRoots(projection: Array<out String>?): Cursor = MatrixCursor(arrayOf("root_id"))

        override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor =
            MatrixCursor(COLUMNS).apply { row(documentId) }

        override fun queryChildDocuments(
            parentDocumentId: String,
            projection: Array<out String>?,
            sortOrder: String?,
        ): Cursor {
            val folder = file(parentDocumentId)
            if (!folder.isDirectory) throw java.io.FileNotFoundException(parentDocumentId)
            return MatrixCursor(COLUMNS).apply {
                folder.listFiles().orEmpty().forEach { row("$parentDocumentId/${it.name}") }
            }
        }

        override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor =
            ParcelFileDescriptor.open(file(documentId), ParcelFileDescriptor.parseMode(mode))

        override fun createDocument(parentDocumentId: String, mimeType: String, displayName: String): String {
            file("$parentDocumentId/$displayName").createNewFile()
            return "$parentDocumentId/$displayName"
        }

        override fun deleteDocument(documentId: String) {
            file(documentId).delete()
        }

        override fun isChildDocument(parentDocumentId: String, documentId: String) =
            documentId.startsWith("$parentDocumentId/")

        private fun MatrixCursor.row(id: String) {
            val file = file(id)
            addRow(
                arrayOf(
                    id,
                    file.name,
                    if (file.isDirectory) Document.MIME_TYPE_DIR else "application/json",
                    file.lastModified(),
                    file.length(),
                ),
            )
        }

        private fun file(id: String) = File(base, id)

        companion object {
            lateinit var base: File
            val COLUMNS = arrayOf(
                Document.COLUMN_DOCUMENT_ID,
                Document.COLUMN_DISPLAY_NAME,
                Document.COLUMN_MIME_TYPE,
                Document.COLUMN_LAST_MODIFIED,
                Document.COLUMN_SIZE,
            )
        }
    }

    private val authority = "app.storyarc.test.documents"
    private val tree = DocumentsContract.buildTreeDocumentUri(authority, "Sync")
    private val resolver = RuntimeEnvironment.getApplication().contentResolver

    init {
        TestDocuments.base = createTempDirectory("sync-folder").toFile()
        File(TestDocuments.base, "Sync").mkdirs()
        val info = ProviderInfo().apply {
            this.authority = this@FolderSyncPlaceTest.authority
            exported = true
            grantUriPermissions = true
            readPermission = android.Manifest.permission.MANAGE_DOCUMENTS
            writePermission = android.Manifest.permission.MANAGE_DOCUMENTS
        }
        Robolectric.buildContentProvider(TestDocuments::class.java).create(info)
    }

    @Test
    fun `a picked folder takes a write, gives it back, and takes an overwrite at that version`() = runTest {
        val place = FolderSyncPlace(resolver, tree)
        assertNull(place.read(NAME))
        assertTrue(place.write(NAME, "one", replacing = null))
        val first = place.read(NAME)!!
        assertEquals("one", first.text)
        assertEquals(listOf(NAME), place.names())

        assertTrue(place.write(NAME, "two, longer", replacing = first.version))
        assertEquals("two, longer", place.read(NAME)?.text)
        assertEquals("two, longer", File(TestDocuments.base, "Sync/$NAME").readText())
    }

    @Test
    fun `a write against a version that changed writes nothing`() = runTest {
        val place = FolderSyncPlace(resolver, tree)
        assertTrue(place.write(NAME, "first", replacing = null))
        assertFalse(place.write(NAME, "second", replacing = null))
        assertFalse(place.write(NAME, "second", replacing = "not-the-version"))
        assertEquals("first", place.read(NAME)?.text)
        assertTrue(place.delete(NAME))
        assertNull(place.read(NAME))
    }

    @Test
    fun `the chosen folder is the same place after a relaunch`() = runTest {
        val preferences = FakePreferences()
        SyncPlaceStore(preferences).choose(SyncPlaceChoice.Folder(tree.toString()))
        FolderSyncPlace(resolver, tree).write(NAME, "kept", replacing = null)

        // A new store over the same preferences is what a relaunch is.
        val chosen = SyncPlaceStore(preferences).choice() as SyncPlaceChoice.Folder
        val place = FolderSyncPlace(resolver, android.net.Uri.parse(chosen.tree))
        assertEquals("kept", place.read(NAME)?.text)
    }

    @Test
    fun `a removed folder throws rather than reading as empty`() = runTest {
        val place = FolderSyncPlace(resolver, tree)
        File(TestDocuments.base, "Sync").deleteRecursively()
        try {
            place.read(NAME)
            fail("a removed folder read as present")
        } catch (expected: Exception) {
            // The runner shows any failure of the place as unreachable.
        }
    }

    private companion object {
        const val NAME = "StoryArc Library.json"
    }
}
