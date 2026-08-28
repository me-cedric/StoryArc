package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Test

class DownloadReorderTest {
    private fun queued(vararg ids: String) = DownloadLibrary(
        downloads = ids.map { Download(id = it, title = it, remote = it, mediaType = "x") },
    )

    @Test
    fun `moves one place later`() {
        val moved = queued("a", "b", "c").moving("a", later = true)
        assertEquals(listOf("b", "a", "c"), moved.downloads.map { it.id })
    }

    @Test
    fun `moves one place earlier`() {
        val moved = queued("a", "b", "c").moving("c", later = false)
        assertEquals(listOf("a", "c", "b"), moved.downloads.map { it.id })
    }

    @Test
    fun `will not move past either end`() {
        val library = queued("a", "b")
        assertEquals(listOf("a", "b"), library.moving("a", later = false).downloads.map { it.id })
        assertEquals(listOf("a", "b"), library.moving("b", later = true).downloads.map { it.id })
    }

    @Test
    fun `leaves a running download where it is`() {
        val library = DownloadLibrary(
            downloads = listOf(
                Download(id = "a", title = "a", remote = "a", mediaType = "x",
                         state = Download.State.Running),
                Download(id = "b", title = "b", remote = "b", mediaType = "x"),
                Download(id = "c", title = "c", remote = "c", mediaType = "x"),
            ),
        )
        // "b" is the first *queued* one, so it cannot go earlier even though "a" is above it.
        assertEquals(listOf("a", "b", "c"), library.moving("b", later = false).downloads.map { it.id })
        assertEquals(listOf("a", "c", "b"), library.moving("b", later = true).downloads.map { it.id })
    }
}
