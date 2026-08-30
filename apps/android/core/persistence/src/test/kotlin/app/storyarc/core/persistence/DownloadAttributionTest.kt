package app.storyarc.core.persistence

import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Tracing a downloaded file back to the source it came from.
 *
 * `library-browsing` requires one library spanning every source, and a file on disk carries
 * no memory of the server it was fetched from. The record does; the directory is what joins
 * the two. iOS's `DownloadStoreTests` asserts the same three cases.
 */
class DownloadAttributionTest {
    @get:Rule
    val folder = TemporaryFolder()

    private fun store(): DownloadStore =
        DownloadStore(StubPreferences(), folder.newFolder("downloads"))

    private fun record(source: UUID?) = Download(
        id = "urn:uuid:7",
        sourceId = source,
        title = "Bone",
        remote = "https://example.test/bone.cbz",
        mediaType = "application/vnd.comicbook+zip",
        state = Download.State.Finished,
    )

    @Test
    fun `a downloaded file is traced back to the source it came from`() {
        val store = store()
        val server = UUID.randomUUID()
        val download = record(server)
        val library = DownloadLibrary(downloads = listOf(download))

        val file = store.location(download.id, "cbz", download.title)
        assertEquals(server, store.download(file, library)?.sourceId)
    }

    @Test
    fun `a file named something else in the same directory is still traced`() {
        // The writers have not always agreed on the file's name -- one stores the title and
        // another the identifier -- and they have always agreed on the directory. Matching
        // on the name would lose half the library's attributions.
        val store = store()
        val download = record(UUID.randomUUID())
        val library = DownloadLibrary(downloads = listOf(download))

        val renamed = store.location(download.id, "cbz")
        assertEquals(download.id, store.download(renamed, library)?.id)
    }

    @Test
    fun `a file no download claims is attributed to nothing`() {
        val store = store()
        val stray = File(File(store.directory, "elsewhere"), "Akira.cbz")
        assertNull(store.download(stray, DownloadLibrary()))
    }
}

/** The store only reads and writes one string; a map is the whole of what it needs. */
private class StubPreferences : android.content.SharedPreferences {
    private val values = mutableMapOf<String, String?>()

    override fun getString(key: String?, defValue: String?): String? = values[key] ?: defValue
    override fun contains(key: String?): Boolean = values.containsKey(key)
    override fun getAll(): MutableMap<String, *> = values
    override fun getStringSet(key: String?, defValues: MutableSet<String>?) = defValues
    override fun getInt(key: String?, defValue: Int) = defValue
    override fun getLong(key: String?, defValue: Long) = defValue
    override fun getFloat(key: String?, defValue: Float) = defValue
    override fun getBoolean(key: String?, defValue: Boolean) = defValue
    override fun registerOnSharedPreferenceChangeListener(
        listener: android.content.SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit
    override fun unregisterOnSharedPreferenceChangeListener(
        listener: android.content.SharedPreferences.OnSharedPreferenceChangeListener?,
    ) = Unit

    override fun edit(): android.content.SharedPreferences.Editor = Editor()

    private inner class Editor : android.content.SharedPreferences.Editor {
        override fun putString(key: String?, value: String?) = apply { values[key!!] = value }
        override fun putStringSet(key: String?, value: MutableSet<String>?) = this
        override fun putInt(key: String?, value: Int) = this
        override fun putLong(key: String?, value: Long) = this
        override fun putFloat(key: String?, value: Float) = this
        override fun putBoolean(key: String?, value: Boolean) = this
        override fun remove(key: String?) = apply { values.remove(key) }
        override fun clear() = apply { values.clear() }
        override fun commit() = true
        override fun apply() = Unit
    }
}
