package app.storyarc.feature.epubreader

import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.KavitaOrigin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The page number a recorded position reports to Kavita, and the address it reports it to.
 *
 * The field report: an EPUB read from Kavita never pushed its position, because this
 * activity reported nothing at all -- it is a separate screen from [ReaderHost], which is
 * the one that already did. `app`'s `PageToReportTest` asserts the same page-number cases;
 * this file also covers [kavitaAddressOf], which that one has no need of.
 */
class PageToReportTest {

    private fun origin(pages: Int) =
        KavitaOrigin(sourceId = "s", libraryId = 1, seriesId = 7, volumeId = 3, chapterId = 42, pages = pages)

    @Test
    fun `a paged position reports its own index, ignoring the chapter's page count`() {
        assertEquals(3, pageToReport(ReadingPosition.Page(3, 10), origin(pages = 0)))
    }

    @Test
    fun `a reflowable position becomes a page, from the chapter's own length`() {
        assertEquals(10, pageToReport(ReadingPosition.Reflowable(0.5, "{}"), origin(pages = 21)))
    }

    @Test
    fun `a reflowable position with no known page count is not reported`() {
        assertNull(pageToReport(ReadingPosition.Reflowable(0.5, "{}"), origin(pages = 0)))
    }

    @Test
    fun `a listening position takes the same rule as a reflowable one`() {
        val listening = ReadingPosition.Listening(part = 1, partCount = 2, offsetMillis = 0, ofMillis = null)
        assertEquals(10, pageToReport(listening, origin(pages = 21)))
    }

    private fun source(
        kind: SourceKind = SourceKind.KAVITA_SERVER,
        locator: String? = "https://kavita.example",
        credentialReference: String? = "ref",
    ) = Source(displayName = "Attic", kind = kind, locator = locator, credentialReference = credentialReference)

    @Test
    fun `a source that is not a Kavita server has no address`() {
        assertNull(kavitaAddressOf(source(kind = SourceKind.LOCAL_FOLDER), credentials = null))
    }

    @Test
    fun `a Kavita source with no locator has no address`() {
        assertNull(kavitaAddressOf(source(locator = null), credentials = null))
    }

    @Test
    fun `a Kavita source with no credential reference has no address`() {
        assertNull(kavitaAddressOf(source(credentialReference = null), credentials = null))
    }

    @Test
    fun `a Kavita source with no secure store has no address`() {
        assertNull(kavitaAddressOf(source(), credentials = null))
    }
}
