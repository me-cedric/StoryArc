package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Filling in a reader-set status for a series whose source reports none.
 *
 * iOS's `SeriesStatusTests` makes the same claims in the same order.
 */
class SeriesStatusTest {

    private fun publication(title: String, series: String?, status: PublicationStatus?) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$title"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        status = status,
        origin = MetadataOrigin.INFERRED,
    )

    @Test
    fun `a series with no reported status takes the one the reader set`() {
        val library = listOf(publication("Watchmen #1", series = "Watchmen", status = null))
        val overlaid = withManualStatuses(library, mapOf("Watchmen" to PublicationStatus.COMPLETED))
        assertEquals(PublicationStatus.COMPLETED, overlaid.single().status)
    }

    @Test
    fun `a series with a reported status keeps it, whatever the reader set`() {
        val library = listOf(
            publication("Saga #1", series = "Saga", status = PublicationStatus.ONGOING),
        )
        val overlaid = withManualStatuses(library, mapOf("Saga" to PublicationStatus.CANCELLED))
        assertEquals(PublicationStatus.ONGOING, overlaid.single().status)
    }

    @Test
    fun `a publication with no series is never given a status`() {
        val library = listOf(publication("One-shot", series = null, status = null))
        // The override is keyed by a series this one-shot does not have, so it is a mistake
        // to apply it even if a stray key happened to be empty and a series name matched it.
        val overlaid = withManualStatuses(library, mapOf("" to PublicationStatus.ONGOING))
        assertNull(overlaid.single().status)
    }

    @Test
    fun `a series with no override at all is left unset`() {
        val library = listOf(publication("Maus #1", series = "Maus", status = null))
        val overlaid = withManualStatuses(library, emptyMap())
        assertNull(overlaid.single().status)
    }
}
