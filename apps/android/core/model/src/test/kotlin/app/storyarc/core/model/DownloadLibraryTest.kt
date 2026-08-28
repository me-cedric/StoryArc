package app.storyarc.core.model

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The same eleven claims iOS's `DownloadLibraryTests` makes. */
class DownloadLibraryTest {

    private fun download(id: String, source: UUID? = null) = Download(
        id = id,
        sourceId = source,
        title = id,
        remote = "https://library.example/$id.epub",
        mediaType = "application/epub+zip",
    )

    @Test
    fun queueingIsIdempotent() {
        // `offline-downloads`: when a publication is already downloaded "the app does not
        // re-fetch it". A second tap on a book being fetched is the common way to ask.
        val library = DownloadLibrary().queueing(download("a")).queueing(download("a"))
        assertEquals(1, library.downloads.size)
    }

    @Test
    fun finishingStampsTheTime() {
        val library = DownloadLibrary().queueing(download("a"))
            .marking("a", Download.State.Finished)
        assertEquals(Download.State.Finished, library["a"]!!.state)
        assertTrue(library["a"]!!.completedAt != null)
    }

    @Test
    fun progressWithoutASizeHasNoFraction() {
        // A bar that never moves is worse than no bar.
        val library = DownloadLibrary().queueing(download("a")).advancing("a", 4096)
        assertNull(library["a"]!!.fraction)
    }

    @Test
    fun progressWithASizeIsAFractionOfIt() {
        val library = DownloadLibrary().queueing(download("a")).advancing("a", 50, 200)
        assertEquals(0.25, library["a"]!!.fraction!!, 0.0001)
    }

    @Test
    fun progressCannotExceedOne() {
        // A server that under-reports its own Content-Length is a real thing, and a progress
        // bar at 140% is how a reader learns not to trust the app.
        val library = DownloadLibrary().queueing(download("a")).advancing("a", 300, 200)
        assertEquals(1.0, library["a"]!!.fraction!!, 0.0001)
    }

    @Test
    fun failuresCountAndTheThirdStopsTheRetries() {
        var library = DownloadLibrary().queueing(download("a"))
        for (attempt in 1..2) {
            library = library.failing("a", "timed out")
            assertEquals(Download.State.Failed("timed out", attempt), library["a"]!!.state)
            assertTrue(DownloadLibrary.shouldRetry(library["a"]!!))
        }
        library = library.failing("a", "timed out")
        assertFalse(DownloadLibrary.shouldRetry(library["a"]!!))
    }

    @Test
    fun backoffDoubles() {
        assertEquals(2000L, DownloadLibrary.backoffMillis(1))
        assertEquals(4000L, DownloadLibrary.backoffMillis(2))
        assertEquals(8000L, DownloadLibrary.backoffMillis(3))
    }

    @Test
    fun aDragDownwardsLandsWhereItWasDropped() {
        val library = DownloadLibrary()
            .queueing(download("a")).queueing(download("b")).queueing(download("c"))
            .moving("a", 2)
        assertEquals(listOf("b", "a", "c"), library.downloads.map { it.id })
    }

    @Test
    fun aDragUpwardsLandsWhereItWasDropped() {
        val library = DownloadLibrary()
            .queueing(download("a")).queueing(download("b")).queueing(download("c"))
            .moving("c", 0)
        assertEquals(listOf("c", "a", "b"), library.downloads.map { it.id })
    }

    @Test
    fun removingASourceTakesItsDownloadsAndNamesThem() {
        // Named, because the caller has files to delete.
        val source = UUID.randomUUID()
        val other = UUID.randomUUID()
        val library = DownloadLibrary()
            .queueing(download("a", source))
            .queueing(download("b", other))
            .queueing(download("c", source))
        val (kept, removed) = library.removingAll(source)
        assertEquals(listOf("b"), kept.downloads.map { it.id })
        assertEquals(listOf("a", "c"), removed.map { it.id })
    }

    @Test
    fun whatIsOnDiskCountsOnlyWhatFinished() {
        val library = DownloadLibrary()
            .queueing(download("a")).queueing(download("b"))
            .advancing("a", 100).marking("a", Download.State.Finished)
            .advancing("b", 40)
        assertEquals(100L, library.bytesOnDisk)
        assertEquals(listOf("b"), library.pending.map { it.id })
        assertEquals(listOf("a"), library.finished.map { it.id })
    }
}
