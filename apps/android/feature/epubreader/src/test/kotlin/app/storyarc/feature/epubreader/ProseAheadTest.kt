package app.storyarc.feature.epubreader

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * The page a turn across a chapter end arrives at is rastered before the navigator moves.
 * Task 4.3b of `reader-theming-and-page-transitions`, owner answer O14. iOS's
 * `ProsePagesTests` asserts the same rules.
 *
 * The view tree here is the shape Readium builds: a `ViewPager` whose pages sit side by side,
 * the current one holding a `WebView`. The neighbour paints a known colour, so a test reads the
 * raster and says whose page it is.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@OptIn(ExperimentalCoroutinesApi::class)
class ProseAheadTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    /** Named as Readium's pager is: the class the finder looks for is `ViewPager`. */
    private class ViewPager(context: Context) : FrameLayout(context)

    /** A page that is still scrollable to the right while [more] holds. */
    private class Column(context: Context, var more: Boolean) : WebView(context) {
        override fun canScrollHorizontally(direction: Int) = more
    }

    private class Painted(context: Context, private val colour: Int) : FrameLayout(context) {
        init {
            setWillNotDraw(false)
        }

        override fun onDraw(canvas: Canvas) = canvas.drawColor(colour)
    }

    private class Book(val root: FrameLayout, val pager: ViewPager, val current: Column)

    /** Two pages of 100 by 200 in a pager, the current one at the left and the next beside it. */
    private fun book(more: Boolean, withNeighbour: Boolean = true, neighbourHeight: Int = 200): Book {
        val root = FrameLayout(context)
        val pager = ViewPager(context)
        val current = Column(context, more)
        val page = FrameLayout(context).apply { addView(current) }
        pager.addView(page)
        if (withNeighbour) pager.addView(Painted(context, Color.RED))
        root.addView(pager)
        root.layout(0, 0, 100, 200)
        pager.layout(0, 0, 100, 200)
        page.layout(0, 0, 100, 200)
        current.layout(0, 0, 100, 200)
        if (withNeighbour) pager.getChildAt(1).layout(100, 0, 200, neighbourHeight)
        return Book(root, pager, current)
    }

    private fun leaving(): Bitmap =
        Bitmap.createBitmap(100, 200, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.BLUE) }

    @Test
    fun `at a chapter end the neighbour is drawn where the current page stands`() {
        val book = book(more = false)

        val raster = ProseAhead.raster(book.root, step = 1, leaving = leaving())

        assertNotNull(raster)
        assertEquals("the neighbour's own page", Color.RED, raster!!.getPixel(50, 100))
        assertEquals(100, raster.width)
    }

    @Test
    fun `inside a chapter there is nothing to raster ahead`() {
        val book = book(more = true)

        assertNull(ProseAhead.raster(book.root, step = 1, leaving = leaving()))
    }

    @Test
    fun `a book with no neighbour in that direction gives none`() {
        assertNull(ProseAhead.raster(book(more = false, withNeighbour = false).root, 1, leaving()))
        // The neighbour lies on the right; a turn to the left has none.
        assertNull(ProseAhead.raster(book(more = false).root, step = -1, leaving = leaving()))
    }

    @Test
    fun `a view with no pager gives none`() {
        assertNull(ProseAhead.raster(FrameLayout(context), 1, leaving()))
    }

    @Test
    fun `the bands outside the neighbour's own bounds are the leaving page's`() {
        // A neighbour shorter than the page, as Readium lays a resource inside the insets.
        val book = book(more = false, neighbourHeight = 100)

        val raster = ProseAhead.raster(book.root, step = 1, leaving = leaving())!!

        assertEquals(Color.RED, raster.getPixel(50, 50))
        assertEquals("not black", Color.BLUE, raster.getPixel(50, 150))
    }

    @Test
    fun `a forward turn goes right in a left-to-right book and left in a right-to-left one`() {
        assertEquals(1, ProseAhead.step(forward = true, isRightToLeft = false))
        assertEquals(-1, ProseAhead.step(forward = false, isRightToLeft = false))
        assertEquals(-1, ProseAhead.step(forward = true, isRightToLeft = true))
        assertEquals(1, ProseAhead.step(forward = false, isRightToLeft = true))
    }

    @Test
    fun `the place of the book changes when the pager does`() {
        val book = book(more = false)
        val before = ProseAhead.place(book.root)

        book.pager.scrollX = 100

        assertNotNull(before)
        assertTrue(ProseAhead.place(book.root) != before)
    }

    // The driver

    private class Page(val ahead: Bitmap?) : ProsePage {
        var arrivedCalls = 0
        var sheet: Sheet? = null

        override fun raise(isRightToLeft: Boolean): ProseSheet = Sheet().also { sheet = it }

        override fun ahead(forward: Boolean, isRightToLeft: Boolean): Bitmap? = ahead

        override suspend fun move(forward: Boolean) = true

        override suspend fun arrived(): Bitmap? {
            arrivedCalls += 1
            return null
        }
    }

    private class Sheet : ProseSheet {
        override var progress = 0f
        override var other: Bitmap? = null
        override val turnWidth = 400f

        override fun remove() = Unit
    }

    @Test
    fun `a page rastered ahead is under the fold at once, and the raster after the move is not taken`() = runTest {
        val picture = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
        val probed = mutableListOf<Boolean>()
        val curl = ProseCurlDriver(
            scope = this,
            density = { 1f },
            spring = { _, _, _ -> },
            probe = { _, ahead -> probed += ahead },
        )
        val page = Page(ahead = picture)

        assertTrue(curl.request(forward = true, page = page, isRightToLeft = false))

        assertSame("under the fold before the navigator has moved", picture, page.sheet!!.other)
        advanceUntilIdle()
        assertEquals(0, page.arrivedCalls)
        assertEquals(listOf(true), probed)
    }

    @Test
    fun `with nothing rastered ahead the arriving page is taken after the move`() = runTest {
        val probed = mutableListOf<Boolean>()
        val curl = ProseCurlDriver(
            scope = this,
            density = { 1f },
            spring = { _, _, _ -> },
            probe = { _, ahead -> probed += ahead },
        )
        val page = Page(ahead = null)

        curl.request(forward = true, page = page, isRightToLeft = false)
        advanceUntilIdle()

        assertEquals(1, page.arrivedCalls)
        assertEquals(listOf(false), probed)
    }

    // The wait

    @Test
    fun `a page that shifts ends the wait before Readium reports where it landed`() = runTest {
        val location = MutableStateFlow("page 4")
        var shifted = false

        assertTrue(movedTo(location, pageShifted = { shifted }) { shifted = true })
    }

    @Test
    fun `a book that neither reports nor shifts did not turn`() = runTest {
        val location = MutableStateFlow("page 9 of 9")

        assertFalse(movedTo(location, pageShifted = { false }) { })
    }

    @Test
    fun `a view with no pager has no place`() {
        assertNull(ProseAhead.place(FrameLayout(context)))
    }
}
