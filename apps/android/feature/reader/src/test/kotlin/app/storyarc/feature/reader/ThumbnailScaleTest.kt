package app.storyarc.feature.reader

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The carousel's size rule. `page-browser-carousel` §1: "the centred page is about 1.6
 * times as wide as its neighbours".
 */
class ThumbnailScaleTest {

    @Test
    fun `the centred page draws 1_6 times as wide as its neighbours`() {
        val centred = pageScale(currentPage = 5, page = 5, currentPageOffsetFraction = 0f)
        val neighbour = pageScale(currentPage = 5, page = 6, currentPageOffsetFraction = 0f)
        assertEquals(1f, centred, 0.001f)
        assertEquals(1.6f, centred / neighbour, 0.001f)
    }

    @Test
    fun `a page halfway to the centre draws between the two sizes`() {
        assertEquals(0.8125f, pageScale(currentPage = 5, page = 6, currentPageOffsetFraction = 0.5f), 0.001f)
    }

    @Test
    fun `a page further away draws at the neighbours' size`() {
        assertEquals(
            pageScale(currentPage = 5, page = 6, currentPageOffsetFraction = 0f),
            pageScale(currentPage = 5, page = 9, currentPageOffsetFraction = 0f),
            0.001f,
        )
    }
}
