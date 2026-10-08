package app.storyarc.core.format

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-sync` task 2.3: the sync folder holds a read and write grant, and the library reads
 * every persisted tree grant as one of its folders. [SafTree.isLibraryGrant] keeps the two apart.
 */
class SafLibraryGrantTest {

    @Test
    fun `a folder picked for the library is a library folder`() {
        assertTrue(SafTree.isLibraryGrant(isRead = true, isWrite = false, isTree = true))
    }

    @Test
    fun `the folder picked for sync is not a library folder`() {
        assertFalse(SafTree.isLibraryGrant(isRead = true, isWrite = true, isTree = true))
    }

    @Test
    fun `a single file handed over is not a library folder`() {
        assertFalse(SafTree.isLibraryGrant(isRead = true, isWrite = false, isTree = false))
    }
}
