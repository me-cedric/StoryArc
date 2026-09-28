package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What a reader is told before a whole shelf is fetched.
 *
 * `collections-and-reading-lists`: downloading a collection or a reading list "states the item
 * count and total size before starting".
 *
 * Both numbers have to describe the fetch. Quoting the size of the whole shelf is the easy
 * mistake and the expensive one: a reader with nine of ten issues already on the device would
 * be told the tenth costs ten issues' worth of data, on a train, on a metered connection.
 *
 * iOS's `BulkDownloadAskTests` asserts these cases one for one.
 */
class BulkDownloadAskTest {

    /** One byte for each publication, so a total says which publications it counted. */
    private val weigh: (Set<String>) -> Long = { it.size.toLong() }

    @Test
    fun `the count is what would be fetched, not what the shelf holds`() {
        val ask = requireNotNull(
            BulkDownloadAsk.of(setOf("a", "b", "c"), setOf("a"), weigh),
        )

        assertEquals(setOf("b", "c"), ask.ids)
    }

    @Test
    fun `the size is weighed for what would be fetched, not for the whole shelf`() {
        var weighed = emptySet<String>()
        val ask = requireNotNull(
            BulkDownloadAsk.of(setOf("a", "b", "c"), setOf("a")) {
                weighed = it
                weigh(it)
            },
        )

        assertEquals(setOf("b", "c"), weighed)
        assertEquals(2L, ask.bytes)
    }

    @Test
    fun `a shelf already on the device is asked nothing`() {
        assertNull(BulkDownloadAsk.of(setOf("a", "b"), setOf("a", "b"), weigh))
    }

    @Test
    fun `an empty shelf is asked nothing either`() {
        assertNull(BulkDownloadAsk.of(emptySet(), emptySet(), weigh))
    }

    @Test
    fun `a shelf of which none is on the device is fetched whole`() {
        val ask = requireNotNull(BulkDownloadAsk.of(setOf("a", "b"), emptySet(), weigh))

        assertEquals(setOf("a", "b"), ask.ids)
        assertEquals(2L, ask.bytes)
    }

    @Test
    fun `nothing is weighed when nothing would be fetched`() {
        // The store is asked for a size only when there is a question to put. A weigh on the
        // way to saying "nothing to do" reads every file for an answer nobody is shown.
        var asked = false
        BulkDownloadAsk.of(setOf("a"), setOf("a")) {
            asked = true
            0L
        }

        assertFalse(asked)
    }
}
