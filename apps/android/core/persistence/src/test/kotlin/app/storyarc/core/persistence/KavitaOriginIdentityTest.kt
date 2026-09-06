package app.storyarc.core.persistence

import app.storyarc.core.model.PublicationIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.UUID

/**
 * ADR-0006's first identity rule, built from what the browser already knows.
 *
 * The browser holds a library, a series, a volume and a chapter for every chapter it opens.
 * Only two of those name the publication: the server it came from and the chapter itself.
 * iOS's `KavitaOriginIdentityTests` asserts the same cases.
 */
class KavitaOriginIdentityTest {

    private fun origin(sourceId: String, chapterId: Int = 42) = KavitaOrigin(
        sourceId = sourceId,
        libraryId = 1,
        seriesId = 7,
        volumeId = 3,
        chapterId = chapterId,
    )

    @Test
    fun `a chapter on a source the app knows becomes a server identifier`() {
        val source = UUID.randomUUID()

        assertEquals(
            PublicationIdentity.ServerIdentifier(source, "42"),
            origin(source.toString()).serverIdentifier,
        )
    }

    @Test
    fun `a source id that is not an identifier yields nothing at all`() {
        // Nothing is invented here. The store keys a server identity by the source's own
        // id, and a guessed one would file two servers as one publication -- data loss in
        // the one store this app promises never to lose.
        assertNull(origin("not-a-uuid").serverIdentifier)
        assertNull(origin("").serverIdentifier)
    }

    @Test
    fun `two chapters on one server are two publications`() {
        val source = UUID.randomUUID()

        assertNotEquals(
            origin(source.toString(), chapterId = 7).serverIdentifier,
            origin(source.toString(), chapterId = 8).serverIdentifier,
        )
    }

    @Test
    fun `the same chapter number on two servers is two publications`() {
        // Kavita numbers chapters per server. Two readers' servers both have a chapter 42
        // and they are different books.
        assertNotEquals(
            origin(UUID.randomUUID().toString()).serverIdentifier,
            origin(UUID.randomUUID().toString()).serverIdentifier,
        )
    }
}
