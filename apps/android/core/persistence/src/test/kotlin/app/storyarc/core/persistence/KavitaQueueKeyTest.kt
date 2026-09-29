package app.storyarc.core.persistence

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The key a held Kavita write is queued under.
 *
 * Two servers can each hold a chapter numbered 12 -- Kavita numbers chapters per server, not
 * globally -- so a key that named only the chapter would let one server's held write erase
 * the other's. iOS's `KavitaQueueKeyTests` asserts the same cases.
 */
class KavitaQueueKeyTest {

    private fun origin(sourceId: String, chapterId: Int = 12) = KavitaOrigin(
        sourceId = sourceId,
        libraryId = 1,
        seriesId = 7,
        volumeId = 3,
        chapterId = chapterId,
    )

    private fun store() = KavitaProgressStore(FakePreferences())

    @Test
    fun `a held position names its server so the same chapter on two servers holds twice`() {
        val store = store()
        store.hold(KavitaUnsent(origin("server-a"), page = 4))
        store.hold(KavitaUnsent(origin("server-b"), page = 9))

        assertEquals(2, store.unsent().size)
        assertEquals(setOf(4, 9), store.unsent().map { it.page }.toSet())
    }

    @Test
    fun `a later position on the same server for the same chapter replaces the held one`() {
        val store = store()
        store.hold(KavitaUnsent(origin("server-a"), page = 4))
        store.hold(KavitaUnsent(origin("server-a"), page = 9))

        assertEquals(1, store.unsent().size)
        assertEquals(9, store.unsent().single().page)
    }

    @Test
    fun `dropping one server's key leaves the other server's held entry alone`() {
        val store = store()
        val a = KavitaUnsent(origin("server-a"), page = 4)
        val b = KavitaUnsent(origin("server-b"), page = 9)
        store.hold(a)
        store.hold(b)

        store.drop(a.key)

        assertEquals(listOf(b), store.unsent())
    }
}
