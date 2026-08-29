package app.storyarc.core.persistence

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingDirection
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The library snapshot: what survives a round trip, and what a bad one costs.
 *
 * iOS's `LibraryCacheTests` asserts the same four things.
 */
class LibraryCacheTest {

    @get:Rule
    val temporary = TemporaryFolder()

    private fun cache() = LibraryCache(File(temporary.root, "library.json"))

    private fun publication(title: String, source: UUID? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = "Bone",
        number = "1",
        authors = listOf("Jeff Smith"),
        origin = MetadataOrigin.EMBEDDED,
        pageCount = 24,
        coverPath = "001.jpg",
        readingDirection = ReadingDirection.RIGHT_TO_LEFT,
        sourceId = source,
    )

    @Test
    fun `a snapshot reads back with its publications intact`() {
        val cache = cache()
        val source = UUID.randomUUID()

        cache.write(
            LibraryCache.Snapshot(
                refreshedAtEpochMillis = 1_700_000_000_000,
                publications = listOf(publication("Bone", source)),
                locations = mapOf("x" to "/comics/Bone.cbz"),
            ),
        )
        val read = requireNotNull(cache.read())

        assertEquals(1_700_000_000_000, read.refreshedAtEpochMillis)
        assertEquals(mapOf("x" to "/comics/Bone.cbz"), read.locations)
        assertEquals(1, read.publications.size)
        // The fields the grid draws from, and the one the library assigns rather than the
        // indexer — a cached publication attributed to nothing is a source with no items.
        val restored = read.publications.first()
        assertEquals("Bone", restored.displayTitle)
        assertEquals("Bone", restored.series)
        assertEquals(24, restored.pageCount)
        assertEquals(ReadingDirection.RIGHT_TO_LEFT, restored.readingDirection)
        assertEquals(source, restored.sourceId)
    }

    @Test
    fun `no snapshot is not an error`() {
        assertNull(cache().read())
    }

    /**
     * A snapshot this build cannot read costs a rescan, which is what a cache miss is for.
     * It must never be a crash, and never a half-restored shelf.
     */
    @Test
    fun `an unreadable snapshot reads as none at all`() {
        File(temporary.root, "library.json").writeText("{ not json")

        assertNull(cache().read())
    }

    @Test
    fun `clearing forgets the shelf`() {
        val cache = cache()
        cache.write(
            LibraryCache.Snapshot(
                refreshedAtEpochMillis = 1,
                publications = listOf(publication("Bone")),
            ),
        )

        cache.clear()

        assertNull(cache.read())
    }
}
