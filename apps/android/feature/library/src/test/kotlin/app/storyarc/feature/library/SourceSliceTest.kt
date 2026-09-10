package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.SourceDiagnosis
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That a count taken from a slice is not stated as a total.
 *
 * `library-browsing`: a source that holds more than was read states that it is partial, and
 * "the number shown is never presented as the whole".
 *
 * **The number was a lie of omission.** Every source is read in a bounded first helping —
 * sixty series from a Kavita server, one feed page from a catalogue, two hundred files or
 * forty listings from a share — because a library that walked a whole server before drawing
 * anything would leave a reader looking at nothing. The source screen then stated the count
 * as "137 titles", and a reader whose server holds five thousand had no way to tell that
 * from a server that holds 137.
 *
 * The three limits are each a different question, so each is asserted: a full page from
 * Kavita, a `next` link from a catalogue, and any of three budgets running out on a share.
 * iOS's `SourceSliceTests` asserts the same.
 */
class SourceSliceTest {

    private fun rows(count: Int) = List(count) {
        Publication(
            identity = PublicationIdentity(contentDigest = "$it"),
            format = PublicationFormat.CBZ,
            displayTitle = "Row $it",
            origin = MetadataOrigin.INFERRED,
        )
    }

    @Test
    fun `a read that reached the end holds nothing back`() {
        val slice = SourceSlice.whole(rows(3))

        assertFalse(slice.holdsMore)
        assertEquals(3, slice.publications.size)
    }

    @Test
    fun `a source that gave nothing held nothing back either`() {
        // A server that refused, or one never configured. "Nothing, and there may be more"
        // would put *At least 0 titles* on the screen, which says less than nothing.
        assertFalse(SourceSlice.none.holdsMore)
        assertTrue(SourceSlice.none.publications.isEmpty())
    }

    @Test
    fun `the diagnosis says at least when the read stopped at its own limit`() {
        val partial = SourceDiagnosis.of(
            source = source(),
            itemCount = 137,
            downloads = emptyList(),
            isPartial = true,
        )

        assertTrue(partial.isPartial)
        assertEquals(137, partial.itemCount)
    }

    @Test
    fun `a source read to its end says the plain number`() {
        val whole = SourceDiagnosis.of(source = source(), itemCount = 12, downloads = emptyList())

        assertFalse(
            "A count that is the whole of a source must not be hedged. *At least 12* for a" +
                " source that holds 12 teaches a reader to distrust the number.",
            whole.isPartial,
        )
    }

    private fun source() = app.storyarc.core.model.Source(
        id = UUID.randomUUID(),
        kind = app.storyarc.core.model.SourceKind.KAVITA_SERVER,
        displayName = "A server",
        locator = "https://x.invalid",
    )
}
