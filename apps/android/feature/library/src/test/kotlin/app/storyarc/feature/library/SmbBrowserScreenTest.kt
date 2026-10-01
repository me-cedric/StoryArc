package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * That a share row's own headers, once read, are never read a second time.
 *
 * `publication-formats` asks the format, the page count, the cover and the streaming state
 * from a row's own headers to reach it as it nears the viewport -- and a tap on that same row
 * has to use what the viewport already found rather than opening the headers again. iOS's
 * `SmbBrowserViewTests` asserts the same case.
 */
class SmbBrowserScreenTest {
    private fun publication(path: String) = Publication(
        identity = PublicationIdentity(normalizedPath = path),
        format = PublicationFormat.CBZ,
        displayTitle = path,
        origin = MetadataOrigin.EMBEDDED,
    )

    @Test
    fun `a path indexed once is cached, and read again on a second call`() = runTest {
        val cache = mutableMapOf<String, Publication>()
        var reads = 0

        val first = cachedOrIndexed(cache, "comics/Bone.cbz") {
            reads += 1
            publication("comics/Bone.cbz")
        }
        val second = cachedOrIndexed(cache, "comics/Bone.cbz") {
            reads += 1
            publication("comics/Bone.cbz")
        }

        assertEquals(1, reads)
        assertEquals(first, second)
    }

    @Test
    fun `two different paths are indexed once each`() = runTest {
        val cache = mutableMapOf<String, Publication>()
        var reads = 0

        cachedOrIndexed(cache, "comics/Bone.cbz") { reads += 1; publication("comics/Bone.cbz") }
        cachedOrIndexed(cache, "comics/Fables.cbz") { reads += 1; publication("comics/Fables.cbz") }

        assertEquals(2, reads)
        assertEquals(2, cache.size)
    }
}
