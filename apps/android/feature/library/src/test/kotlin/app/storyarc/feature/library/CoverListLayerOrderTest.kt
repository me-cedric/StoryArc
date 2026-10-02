package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The list row thumbnail's paint order: the cover (or its placeholder) first, so a mark drawn
 * after it is not painted over the moment a cover image arrives.
 *
 * `library-browsing`: a list row paints the on-device mark under the thumbnail when the cover
 * draws last. iOS has no equivalent case -- its list row uses an `.overlay`, which always
 * draws after the content it decorates.
 */
class CoverListLayerOrderTest {

    @Test
    fun `with neither mark, only the cover paints`() {
        assertEquals(
            listOf(CoverListLayer.COVER),
            coverListLayerOrder(isKept = false, showsFinished = false),
        )
    }

    @Test
    fun `the on-device mark paints after the cover`() {
        assertEquals(
            listOf(CoverListLayer.COVER, CoverListLayer.ON_DEVICE_MARK),
            coverListLayerOrder(isKept = true, showsFinished = false),
        )
    }

    @Test
    fun `the finished mark paints after the cover`() {
        assertEquals(
            listOf(CoverListLayer.COVER, CoverListLayer.FINISHED_MARK),
            coverListLayerOrder(isKept = false, showsFinished = true),
        )
    }

    @Test
    fun `both marks paint after the cover, on-device first`() {
        assertEquals(
            listOf(CoverListLayer.COVER, CoverListLayer.ON_DEVICE_MARK, CoverListLayer.FINISHED_MARK),
            coverListLayerOrder(isKept = true, showsFinished = true),
        )
    }
}
