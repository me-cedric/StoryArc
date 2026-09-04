package app.storyarc.feature.library

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The window the publication page could not be used in, and the windows that must not move.
 *
 * The rooms below are measured off the real chrome: the status bar (24 dp), the app bar
 * (152 dp expanded with a subtitle, 64 dp when the window is short) and the navigation bar
 * with its gesture inset (88 dp), which the navigation suite takes before this page is laid
 * out at all.
 */
class DetailHeroLayoutTest {

    @Test
    fun aLandscapePhoneLaysTheActionBesideTheCover() {
        // 800 x 360 dp, the short app bar: 360 - 24 - 64 - 88.
        val layout = DetailHeroLayout.of(windowHeight = 360.dp, room = 184.dp)

        assertTrue(layout.isSideBySide)
        // The room, less the page's 16 dp above and below and the hero's 24 dp per edge.
        assertEquals(104.dp, layout.coverHeight)
    }

    @Test
    fun aLandscapePhoneHeroFitsTheRoomItWasGiven() {
        val room = 184.dp
        val layout = DetailHeroLayout.of(windowHeight = 360.dp, room = room)

        // 16 above + 24 + cover + 24 + 16 below. Nothing is left below the fold, which is
        // the whole point: there was no way to start the book in this window.
        val used = 16.dp * 2 + 24.dp * 2 + layout.coverHeight
        assertTrue("hero used $used of $room", used <= room)
    }

    @Test
    fun aPortraitPhoneIsUntouched() {
        // 411 x 914 dp: 914 - 24 - 152 - 88.
        val layout = DetailHeroLayout.of(windowHeight = 914.dp, room = 650.dp)

        assertFalse(layout.isSideBySide)
        // Exactly what it drew before this existed: two fifths of the window, capped —
        // 914 dp is already tall enough for the cap to be the binding constraint.
        assertEquals(360.dp, layout.coverHeight)
    }

    @Test
    fun aTabletKeepsItsCap() {
        val layout = DetailHeroLayout.of(windowHeight = 1280.dp, room = 1100.dp)

        assertFalse(layout.isSideBySide)
        assertEquals(360.dp, layout.coverHeight)
    }

    @Test
    fun theTwoPaneWindowStillStacks() {
        // 1280 x 576 dp: 576 - 24 - 152.
        val layout = DetailHeroLayout.of(windowHeight = 576.dp, room = 400.dp)

        assertFalse(layout.isSideBySide)
        assertEquals(576.dp * 0.4f, layout.coverHeight)
    }

    @Test
    fun theArtworkIsNeverShrunkToAFavicon() {
        // A freeform slot with almost nothing in it. There is a scroll either way here; a
        // 20 dp cover would be the page giving up rather than degrading.
        val layout = DetailHeroLayout.of(windowHeight = 200.dp, room = 90.dp)

        assertTrue(layout.isSideBySide)
        assertEquals(72.dp, layout.coverHeight)
    }

    @Test
    fun besideNeverDrawsAnArtworkBiggerThanStackedWould() {
        // A wide, shallow window where the room happens to exceed two fifths of the height.
        val layout = DetailHeroLayout.of(windowHeight = 400.dp, room = 300.dp)

        assertTrue(layout.isSideBySide)
        assertEquals(400.dp * 0.4f, layout.coverHeight)
    }
}
