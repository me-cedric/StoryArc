package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.smb.SmbAddress
import app.storyarc.core.smb.SmbEntry
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A share's first read hands its frontier to the continuation, instead of the continuation
 * walking the share's root a second time.
 *
 * `SmbContributorTest` already proves the walk itself resumes from a frontier it is handed.
 * It proves it by passing `first.queue` by hand, which is exactly why it could not see that
 * nothing seeded [LibraryViewModel.smbQueues] -- the first read called a wrapper that threw
 * the queue away, so the continuation's cursor fell back to the share's root, listed it
 * again, and adopted every row it already held. The reader saw the number on the source
 * detail screen grow to about twice the share's real one. This test drives the view model,
 * which is where that seam actually is.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SmbFirstReadCarriesItsFrontierTest {

    private val sourceId = UUID.randomUUID()
    private val address = SmbAddress(host = "nas.local", share = "Comics")

    private fun library(): LibraryViewModel {
        val library = LibraryViewModel(ApplicationProvider.getApplicationContext<Application>())
        library.addSource(Source(id = sourceId, displayName = "Attic", kind = SourceKind.NETWORK_SHARE))
        return library
    }

    /** A root with [count] sibling folders, each holding one file. */
    private fun wideTree(count: Int): Map<String, List<SmbEntry>> = buildMap {
        put("", (0 until count).map { SmbEntry(name = "d$it", path = "d$it", isDirectory = true, length = 0) })
        for (i in 0 until count) {
            put("d$i", listOf(SmbEntry(name = "f.cbz", path = "d$i/f.cbz", isDirectory = false, length = 1)))
        }
    }

    @Test
    fun `the first continuation page resumes the frontier the share read stopped at, not the root`() = runTest {
        // Wider than the folder budget, so the first page is proven to stop with folders
        // still unlisted rather than finishing the share.
        val tree = wideTree(SmbContributor.MAX_FOLDERS + 6)
        val listed = mutableListOf<String>()
        suspend fun list(path: String) = tree[path].orEmpty().also { listed += path }

        // What `ServerLibrary.read` now does for a share: one page from the share's root,
        // and the frontier it stopped at carried out of the read with the slice.
        val first = SmbContributor.page(sourceId, address, queue = listOf(address.path), ::list)
        assertTrue("a share wider than the folder budget must report it holds more", first.slice.holdsMore)

        val library = library()
        library.adoptPartialSources(setOf(sourceId), smbFrontiers = mapOf(sourceId to first.queue))
        assertEquals(first.queue, library.smbQueues[sourceId])

        // What `continueReadingShares` then asks its first page for, fallback included.
        listed.clear()
        val second = SmbContributor.page(sourceId, address, library.smbQueues[sourceId] ?: listOf(address.path), ::list)

        // Delete the `smbFrontiers` seeding in `adoptPartialSources` and both of these fail:
        // the cursor falls back to the share's root, so "" is listed a second time and every
        // row the first page already adopted is counted again.
        assertFalse("the share's root must not be walked twice", listed.contains(""))
        val adopted = first.slice.publications + second.slice.publications
        assertEquals(
            "two pages of one share must adopt each file once",
            adopted.size,
            adopted.distinctBy { it.identity.normalizedPath }.size,
        )
        assertEquals(SmbContributor.MAX_FOLDERS + 6, adopted.size)
    }
}
