package app.storyarc.feature.epubreader

import app.storyarc.core.designsystem.navigation.hingeSpreadSplit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Task 19.5's EPUB half: the navigator's own width and gravity, derived from a hinge split
 * the same way `feature/reader`'s lone page is. No Robolectric — [epubHingeLayout] never
 * touches an Android class, which is the whole reason [EpubHingeLayout] exists apart from
 * `FrameLayout.LayoutParams`.
 */
class EpubHingeLayoutTest {

    @Test
    fun `no hinge to avoid matches the parent, ungravitated`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = null, hingeEnd = null)

        val layout = epubHingeLayout(split)

        assertNull(layout.widthPx)
        assertEquals(HingeEdge.NONE, layout.edge)
    }

    @Test
    fun `a hinge nearer the start pins the navigator to the trailing edge`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = 100f, hingeEnd = 140f)

        val layout = epubHingeLayout(split)

        assertEquals(660, layout.widthPx)
        assertEquals(HingeEdge.END, layout.edge)
    }

    @Test
    fun `a hinge nearer the end pins the navigator to the leading edge`() {
        val split = hingeSpreadSplit(containerWidth = 800f, hingeStart = 660f, hingeEnd = 700f)

        val layout = epubHingeLayout(split)

        assertEquals(660, layout.widthPx)
        assertEquals(HingeEdge.START, layout.edge)
    }
}
