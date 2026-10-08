package app.storyarc.core.model

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The folder the app writes and the widget reads, asserted against the same table as iOS's
 * `ReadingSnapshotStoreTests`. Add a case here, add it there.
 */
class ReadingSnapshotStoreTest {

    @get:Rule val temporary = TemporaryFolder()

    private val store by lazy { ReadingSnapshotStore(temporary.newFolder("widget")) }

    private fun snapshot(title: String, percent: Int? = 10) =
        ReadingSnapshot.make("path:/library/$title", title, null, percent)

    private val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte())

    @Test
    fun `an empty folder holds no snapshot`() {
        assertNull(store.read())
    }

    @Test
    fun `a written snapshot and its cover are read back`() = runTest {
        val bone = snapshot("Bone 1")
        assertTrue(store.write(bone) { jpeg })
        assertEquals(bone, store.read())
        assertArrayEquals(jpeg, store.cover(bone)!!.readBytes())
    }

    @Test
    fun `the same snapshot again changes nothing and decodes no cover`() = runTest {
        val bone = snapshot("Bone 1")
        store.write(bone) { jpeg }
        var asked = 0
        assertFalse(store.write(bone) { asked++; jpeg })
        assertEquals(0, asked)
    }

    @Test
    fun `a new percent is written, and keeps the cover`() = runTest {
        store.write(snapshot("Bone 1", percent = 10)) { jpeg }
        val further = snapshot("Bone 1", percent = 11)
        assertTrue(store.write(further) { null })
        assertEquals(further, store.read())
        assertNotNull(store.cover(further))
    }

    @Test
    fun `another book removes the previous cover, and shows none until its own is written`() = runTest {
        val bone = snapshot("Bone 1")
        store.write(bone) { jpeg }
        val saga = snapshot("Saga 1")
        store.write(saga) { null }

        assertEquals(saga, store.read())
        assertNull(store.cover(saga))
        assertNull(store.cover(bone))
    }

    @Test
    fun `no book to continue clears the snapshot and the cover`() = runTest {
        val bone = snapshot("Bone 1")
        store.write(bone) { jpeg }
        assertTrue(store.write(null) { jpeg })
        assertNull(store.read())
        assertNull(store.cover(bone))
        assertFalse(store.write(null) { jpeg })
    }

    @Test
    fun `a record another version wrote is not shown`() {
        store.folder.mkdirs()
        store.folder.resolve(ReadingSnapshotStore.SNAPSHOT_FILE)
            .writeText("""{"version":0,"publicationID":"a","title":"Bone 1"}""")
        assertNull(store.read())
    }
}
