package app.storyarc.feature.reader

import androidx.compose.ui.unit.LayoutDirection
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Spec line 44: the page slider is mirrored under right-to-left, so page one sits at the
 * right end.
 */
class PageSliderMirrorTest {
    @Test
    fun `left-to-right keeps the ordinary track direction`() {
        assertEquals(LayoutDirection.Ltr, sliderLayoutDirection(isRightToLeft = false))
    }

    @Test
    fun `right-to-left mirrors the track`() {
        assertEquals(LayoutDirection.Rtl, sliderLayoutDirection(isRightToLeft = true))
    }
}
