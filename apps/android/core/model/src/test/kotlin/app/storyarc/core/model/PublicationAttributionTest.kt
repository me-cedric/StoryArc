package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.UUID

/**
 * Which source a publication came from.
 *
 * `library-browsing` needs it to order two sources holding one title, and `sources` needs
 * it for a source's item count. Neither was answerable before, which is why a flat list of
 * files was as far as the library could go. iOS's `PublicationAttributionTests` asserts the
 * same two things.
 */
class PublicationAttributionTest {
    @Test
    fun `a publication carries no source until one attributes it`() {
        // Null means unattributed rather than local. A file the system hands over belongs
        // to no source the reader configured, and claiming otherwise would put it in a
        // source's item count.
        val publication = Publication(
            identity = PublicationIdentity(normalizedPath = "/comics/one.cbz"),
            format = PublicationFormat.CBZ,
            displayTitle = "One",
            origin = MetadataOrigin.INFERRED,
        )

        assertNull(publication.sourceId)
    }

    @Test
    fun `attributing a publication keeps everything else about it`() {
        // A copy, not a mutation: the indexer's answer about what a publication *is* must
        // survive the library's answer about where it came from.
        val source = UUID.randomUUID()
        val publication = Publication(
            identity = PublicationIdentity(contentDigest = "digest"),
            format = PublicationFormat.EPUB,
            displayTitle = "Two",
            series = "A series",
            origin = MetadataOrigin.EMBEDDED,
        )

        val attributed = publication.copy(sourceId = source)

        assertEquals(source, attributed.sourceId)
        assertEquals(publication.displayTitle, attributed.displayTitle)
        assertEquals(publication.series, attributed.series)
        assertEquals(publication.identity, attributed.identity)
        assertNull(publication.sourceId)
    }
}
