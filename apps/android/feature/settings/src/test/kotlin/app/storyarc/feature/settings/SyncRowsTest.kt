package app.storyarc.feature.settings

import android.content.Intent
import android.net.Uri
import app.storyarc.core.model.LibraryDocumentFailure
import app.storyarc.core.persistence.SyncPlaceChoice
import app.storyarc.core.persistence.SyncStatus
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.w3c.dom.Element

/**
 * `library-sync` tasks 2.1, 2.3, 2.4 and 4.4: the Sync rows of the Sources group. iOS's
 * `SyncSettingsSectionTests` makes the same claims.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SyncRowsTest {

    private val now = 1_760_000_000_000L

    private val resolver = RuntimeEnvironment.getApplication().contentResolver
    private val readWrite = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    private val tree = Uri.parse("content://com.android.externalstorage.documents/tree/primary%3ASync")

    @Test
    fun `an unreachable place is said in words that name it, and off says nothing`() {
        assertEquals(R.string.sync_status_unreachable to true, syncStatusLine(SyncStatus.Unreachable))
        assertNull(syncStatusLine(SyncStatus.Off))
        assertEquals(R.string.sync_status_idle to false, syncStatusLine(SyncStatus.Idle))
        assertEquals(R.string.sync_status_synced_on to false, syncStatusLine(SyncStatus.Synced(1L)))
        assertEquals(R.string.sync_status_synced_now to false, syncStatusLine(SyncStatus.Synced(now - 1_000), now))
    }

    @Test
    fun `a document the app cannot read is named for why`() {
        assertEquals(
            R.string.sync_status_newer to false,
            syncStatusLine(SyncStatus.Refused(LibraryDocumentFailure.NewerThanThisApp(found = 9, understood = 1))),
        )
        assertEquals(
            R.string.sync_status_not_library to false,
            syncStatusLine(SyncStatus.Refused(LibraryDocumentFailure.NotALibraryDocument)),
        )
    }

    @Test
    fun `a picked folder is held for reading and writing`() {
        assertNull(SyncFolderGrant.take(resolver, tree))
        val held = resolver.persistedUriPermissions.single { it.uri == tree }
        assertTrue(held.isReadPermission && held.isWritePermission)
    }

    @Test
    fun `a folder that already is a library is refused, and keeps its read-only grant`() {
        resolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        assertEquals(R.string.sync_folder_is_library, SyncFolderGrant.take(resolver, tree))
        assertFalse(resolver.persistedUriPermissions.single { it.uri == tree }.isWritePermission)
    }

    @Test
    fun `leaving the folder gives its grant back, and staying keeps it`() {
        resolver.takePersistableUriPermission(tree, readWrite)
        val folder = SyncPlaceChoice.Folder(tree.toString())

        SyncFolderGrant.releaseIfLeaving(resolver, folder, folder)
        assertTrue(resolver.persistedUriPermissions.any { it.uri == tree })

        SyncFolderGrant.releaseIfLeaving(resolver, folder, null)
        assertTrue(resolver.persistedUriPermissions.none { it.uri == tree })
    }

    @Test
    fun `search finds the sync rows in the Sources group`() {
        val match = SettingsGroup.search("sync").single()
        assertEquals(SettingsAnchor.SYNC, match.anchor)
        assertEquals(SettingsGroup.SOURCES, match.group)
    }

    @Test
    fun `every sync string is written in English, French, German and Spanish`() {
        val english = syncStrings("values")
        assertTrue("English defines too few sync strings: ${english.size}", english.size >= 17)
        for (folder in listOf("values-fr", "values-de", "values-es")) {
            val translated = syncStrings(folder)
            assertEquals("$folder lacks or adds a sync string", english.keys, translated.keys)
            for ((name, text) in translated) {
                assertTrue("$folder $name is empty", text.isNotBlank())
                if (name != "sync_place") assertNotEquals("$folder $name is the English text", english[name], text)
            }
        }
    }

    @Test
    fun `the setting states what Android does, with the 15-minute floor`() {
        for (folder in listOf("values", "values-fr", "values-de", "values-es")) {
            assertTrue("$folder sync_when", syncStrings(folder).getValue("sync_when").contains("15"))
        }
    }

    private fun syncStrings(folder: String): Map<String, String> {
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder()
            .parse(File("src/main/res/$folder/strings.xml"))
        val nodes = document.documentElement.getElementsByTagName("string")
        return (0 until nodes.length).map { nodes.item(it) as Element }
            .filter { it.getAttribute("name").startsWith("sync_") }
            .associate { it.getAttribute("name") to it.textContent }
    }
}
