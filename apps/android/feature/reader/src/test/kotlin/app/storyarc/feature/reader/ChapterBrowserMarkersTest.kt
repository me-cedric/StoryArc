package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The rules behind the page browser carousel's chapter name and badge, and the
 * slider's ticks. iOS's `ChapterBrowserMarkersTests` asserts the same table.
 */
class ChapterBrowserMarkersTest {

    private val markers = listOf(
        ChapterMarker(0, "Prologue"),
        ChapterMarker(40, null),
        ChapterMarker(90, "12"),
    )

    @Test
    fun `the name above the carousel is the nearest chapter at or before the centred page`() {
        assertEquals(ChapterLabel.Named("Prologue"), ChapterBrowser.chapterLabel(10, markers))
        assertEquals(ChapterLabel.Position(2), ChapterBrowser.chapterLabel(40, markers))
        assertEquals(ChapterLabel.Named("12"), ChapterBrowser.chapterLabel(200, markers))
    }

    @Test
    fun `before the first chapter starts, the carousel names nothing`() {
        val laterMarkers = listOf(ChapterMarker(5, "One"))
        assertNull(ChapterBrowser.chapterLabel(0, laterMarkers))
    }

    @Test
    fun `no chapter markers at all draws no name`() {
        assertNull(ChapterBrowser.chapterLabel(0, emptyList()))
    }

    @Test
    fun `the badge reads a purely numeric title as the chapter's number`() {
        assertEquals("#12", ChapterBrowser.badgeText(90, markers))
    }

    @Test
    fun `a title that is not only digits falls back to the chapter's position`() {
        assertEquals("#1", ChapterBrowser.badgeText(0, markers))
    }

    @Test
    fun `a marker with no title falls back to its position`() {
        assertEquals("#2", ChapterBrowser.badgeText(40, markers))
    }

    @Test
    fun `a page that does not start a chapter carries no badge`() {
        assertNull(ChapterBrowser.badgeText(41, markers))
    }

    @Test
    fun `tick fractions place each chapter start proportionally along the track`() {
        val fractions = ChapterBrowser.tickFractions(
            markers = listOf(ChapterMarker(0, null), ChapterMarker(50, null)),
            pageCount = 101,
        )
        assertEquals(listOf(0.0f, 0.5f), fractions)
    }

    @Test
    fun `one page or none gives no ticks to place`() {
        assertEquals(emptyList<Float>(), ChapterBrowser.tickFractions(markers, pageCount = 1))
        assertEquals(emptyList<Float>(), ChapterBrowser.tickFractions(markers, pageCount = 0))
    }

    @Test
    fun `comic markers come from the archive's declared starts and titles, sorted`() {
        val built = ChapterBrowser.markers(listOf(40, 0), mapOf(0 to "Prologue"))
        assertEquals(
            listOf(ChapterMarker(0, "Prologue"), ChapterMarker(40, null)),
            built,
        )
    }

    @Test
    fun `right-to-left mirrors the carousel's display order`() {
        assertEquals(0, ChapterBrowser.displayIndex(0, pageCount = 10, isRightToLeft = false))
        assertEquals(9, ChapterBrowser.displayIndex(0, pageCount = 10, isRightToLeft = true))
        assertEquals(5, ChapterBrowser.displayIndex(4, pageCount = 10, isRightToLeft = true))
    }
}
