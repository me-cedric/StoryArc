package app.storyarc.core.persistence

import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Task 28.5: a folder audiobook's position written before its digest existed is found again.
 *
 * On this platform the app's data directory keeps its path across a reinstall, so a position
 * restored with the folder's old path is found by that path; one carried by a sync or an
 * import from a device with another path is found by the folder's digest once the scan has
 * linked it. iOS's `ProgressStoreContainerTests` makes the same claims for its container paths.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FolderPositionAfterReinstallTest {

    private val path = "/data/user/0/app.storyarc/files/downloads/sea-room"
    private val position = ReadingPosition.Listening(part = 1, partCount = 3, offsetMillis = 5_000, ofMillis = 90_000)

    @Test
    fun `a position keyed by the path alone is found once the folder has a digest too`() = runTest {
        val store = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        store.save(ReadingProgress(PublicationIdentity(normalizedPath = path), position, updatedAtEpochMillis = 1))

        val scanned = PublicationIdentity(contentDigest = "folder-d1", normalizedPath = path)

        assertEquals(position, store.progress(scanned)?.position)
        assertTrue(store.link(scanned))
        // Linked, the record is found by the digest alone: the path of another install may differ.
        assertEquals(position, store.progress(PublicationIdentity(contentDigest = "folder-d1", normalizedPath = "/elsewhere/sea-room"))?.position)
    }

    @Test
    fun `a position carried with the digest is found at a new path`() = runTest {
        val store = ProgressStore.inMemory(RuntimeEnvironment.getApplication())
        store.save(ReadingProgress(PublicationIdentity(contentDigest = "folder-d1", normalizedPath = "/old/sea-room"), position, updatedAtEpochMillis = 1))

        assertEquals(position, store.progress(PublicationIdentity(contentDigest = "folder-d1", normalizedPath = path))?.position)
    }
}
