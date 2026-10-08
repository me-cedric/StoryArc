package app.storyarc.feature.epubreader

import android.graphics.Bitmap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The finger drives the curl over prose, with the comic reader's release rule. Task 8.12,
 * owner answer O1. iOS's `ProseCurlTests` and `ProseCurlOnABookTests` assert the same rules.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ProseCurlTest {

    private val forward = ProseCurl(isForward = true, isRightToLeft = false)
    private val backward = ProseCurl(isForward = false, isRightToLeft = false)

    // The rule

    @Test
    fun `the first sideways travel picks the turn, and right-to-left mirrors it`() {
        assertEquals(forward, ProseCurl.starting(-12f, isRightToLeft = false))
        assertEquals(backward, ProseCurl.starting(12f, isRightToLeft = false))
        assertEquals(true, ProseCurl.starting(12f, isRightToLeft = true)?.isForward)
        assertNull(ProseCurl.starting(0f, isRightToLeft = false))
    }

    @Test
    fun `the page follows the finger, in the turn's own direction only`() {
        assertEquals(0.3f, forward.progress(0f, -300f, 1000f), 0.001f)
        // Back past where it started: the navigator moved forward, so the page lies flat.
        assertEquals(0f, forward.progress(0f, 300f, 1000f), 0f)
        assertEquals(-0.3f, backward.progress(0f, 300f, 1000f), 0.001f)
        assertEquals(0f, backward.progress(0f, -300f, 1000f), 0f)
        // A drag that caught a settle at 0.8 counts from 0.8.
        assertEquals(0.7f, forward.progress(0.8f, 100f, 1000f), 0.001f)
    }

    @Test
    fun `released past halfway the turn completes, before it the page springs back`() {
        assertEquals(1f, forward.target(0.6f, 0f), 0f)
        assertEquals(0f, forward.target(0.4f, 0f), 0f)
        assertEquals(-1f, backward.target(-0.6f, 0f), 0f)
        assertEquals(0f, backward.target(-0.4f, 0f), 0f)
    }

    @Test
    fun `a flick completes a short turn, and a flick the other way springs it back`() {
        // 2000 dp a second leftwards is past the 800 a flick needs.
        assertEquals(1f, forward.target(0.1f, -2000f), 0f)
        assertEquals(0f, forward.target(0.1f, 2000f), 0f)
        assertEquals(-1f, backward.target(-0.1f, 2000f), 0f)
        // A page that never left flat is not a turn, however fast the finger left it.
        assertEquals(0f, forward.target(0.01f, -2000f), 0f)
    }

    @Test
    fun `the sheet turns the leaving page forward, and rolls the arriving page in going back`() {
        val ahead = proseSheets(0.3f, "leaving", "arriving")
        assertEquals("leaving", ahead.turning)
        assertEquals("arriving", ahead.under)
        assertEquals(0.3f, ahead.progress, 0.001f)

        val back = proseSheets(-0.3f, "leaving", "arriving")
        assertEquals("arriving", back.turning)
        assertEquals("leaving", back.under)
        assertEquals(0.7f, back.progress, 0.001f)
    }

    @Test
    fun `with no arriving page yet, the leaving page lies flat whatever the finger did`() {
        val sheets = proseSheets(0.4f, "leaving", null)
        assertEquals("leaving", sheets.turning)
        assertEquals(0f, sheets.progress, 0f)
    }

    // The driver, over a book that records its moves

    private class Sheet : ProseSheet {
        override var progress = 0f
        override var other: Bitmap? = null
        override val turnWidth = 400f
        var removed = false

        override fun remove() {
            removed = true
        }
    }

    private class Book(private val canMove: Boolean = true, private val canGoBack: Boolean = true) : ProsePage {
        val moves = mutableListOf<Boolean>()
        var sheet: Sheet? = null

        override fun raise(isRightToLeft: Boolean): ProseSheet = Sheet().also { sheet = it }

        override fun ahead(forward: Boolean, isRightToLeft: Boolean): Bitmap? = null

        override suspend fun move(forward: Boolean): Boolean {
            moves += forward
            return canMove && (forward || canGoBack)
        }

        override suspend fun arrived(): Bitmap? = null
    }

    /** A spring that lands at once, or waits for [gate] when one is set. */
    private class Spring {
        var gate: CompletableDeferred<Unit>? = null
        val targets = mutableListOf<Float>()

        suspend fun run(from: Float, to: Float, onFrame: (Float) -> Unit) {
            targets += to
            onFrame((from + to) / 2)
            gate?.await()
            onFrame(to)
        }
    }

    private fun TestScope.driver(spring: Spring) =
        ProseCurlDriver(scope = this, density = { 2f }, spring = spring::run)

    @Test
    fun `a drag released past halfway turns one page, and one released short puts it back`() = runTest {
        val spring = Spring()
        val curl = driver(spring)
        val book = Book()

        curl.drag(ProseDrag.Began(-10f), book, isRightToLeft = false)
        assertTrue(curl.isTurning)
        curl.drag(ProseDrag.Changed(-250f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Ended(-250f, 0f), book, isRightToLeft = false)
        advanceUntilIdle()
        assertEquals(listOf(true), book.moves)
        assertEquals(listOf(1f), spring.targets)
        assertFalse(curl.isTurning)
        assertTrue(book.sheet!!.removed)

        book.moves.clear()
        curl.drag(ProseDrag.Began(-10f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Changed(-100f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Ended(-100f, 0f), book, isRightToLeft = false)
        advanceUntilIdle()
        assertEquals("forward under the sheet, then back", listOf(true, false), book.moves)
        assertFalse(curl.isTurning)
    }

    @Test
    fun `the fold follows the finger while the drag lasts`() = runTest {
        val curl = driver(Spring())
        val book = Book()

        curl.drag(ProseDrag.Began(-10f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Changed(-130f), book, isRightToLeft = false)

        assertEquals(0.3f, book.sheet!!.progress, 0.001f)
    }

    @Test
    fun `a flick is read in dp, so a short fast drag completes`() = runTest {
        val spring = Spring()
        val curl = driver(spring)
        val book = Book()

        curl.drag(ProseDrag.Began(-10f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Changed(-50f), book, isRightToLeft = false)
        // 4000 px/s at a density of 2 is 2000 dp/s, past the 800 a flick needs.
        curl.drag(ProseDrag.Ended(-50f, -4000f), book, isRightToLeft = false)
        advanceUntilIdle()

        assertEquals(listOf(1f), spring.targets)
        assertEquals(listOf(true), book.moves)

        // 1200 px/s is past 800 as pixels, and short of it as dp at a density of 2.
        curl.drag(ProseDrag.Began(-10f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Changed(-50f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Ended(-50f, -1200f), book, isRightToLeft = false)
        advanceUntilIdle()

        assertEquals(listOf(1f, 0f), spring.targets)
    }

    @Test
    fun `a drag that catches a settle takes it over, and can take the turn back`() = runTest {
        val spring = Spring().apply { gate = CompletableDeferred() }
        val curl = driver(spring)
        val book = Book()

        curl.drag(ProseDrag.Began(-10f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Changed(-300f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Ended(-300f, 0f), book, isRightToLeft = false)
        advanceUntilIdle()
        val caught = book.sheet!!.progress
        assertTrue("the settle is mid-spring", caught > 0.7f && caught < 1f)

        val caughtSpring = spring.gate!!
        spring.gate = null
        curl.drag(ProseDrag.Began(10f), book, isRightToLeft = false)
        // The caught spring would land now; taken over, it must not finish the turn.
        caughtSpring.complete(Unit)
        advanceUntilIdle()
        assertTrue(curl.isTurning)
        curl.drag(ProseDrag.Changed(11f), book, isRightToLeft = false)
        assertEquals("taken over where it was drawn", caught - 1f / 400f, book.sheet!!.progress, 0.001f)
        curl.drag(ProseDrag.Changed(400f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Ended(400f, 0f), book, isRightToLeft = false)
        advanceUntilIdle()

        assertEquals("forward under the sheet, then back", listOf(true, false), book.moves)
        assertFalse(curl.isTurning)
    }

    @Test
    fun `a tap rolls the page over with the same spring, one page on`() = runTest {
        val spring = Spring()
        val curl = driver(spring)
        val book = Book()

        assertTrue(curl.request(forward = true, page = book, isRightToLeft = false))
        advanceUntilIdle()

        assertEquals(listOf(1f), spring.targets)
        assertEquals(listOf(true), book.moves)
        assertFalse(curl.isTurning)
    }

    @Test
    fun `a spring that outlives its own sheet leaves the next turn alone`() = runTest {
        val spring = Spring().apply { gate = CompletableDeferred() }
        val curl = driver(spring)
        val book = Book(canGoBack = false)

        // At the first page: a drag back is released short, and its sheet goes while it springs.
        curl.drag(ProseDrag.Began(10f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Changed(60f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Ended(60f, 0f), book, isRightToLeft = false)
        advanceUntilIdle()
        assertFalse(curl.isTurning)

        // A drag forward starts while that spring still runs, and then the spring lands.
        val lateSpring = spring.gate!!
        spring.gate = null
        curl.drag(ProseDrag.Began(-10f), book, isRightToLeft = false)
        advanceUntilIdle()
        lateSpring.complete(Unit)
        advanceUntilIdle()

        assertTrue("the late spring must not take the new sheet off", curl.isTurning)
        assertEquals("one move back that failed, then one forward", listOf(false, true), book.moves)

        curl.drag(ProseDrag.Changed(-300f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Ended(-300f, 0f), book, isRightToLeft = false)
        advanceUntilIdle()
        assertEquals(listOf(false, true), book.moves)
        assertFalse(curl.isTurning)
    }

    @Test
    fun `at the end of the book a drag lifts nothing and the sheet goes`() = runTest {
        val spring = Spring()
        val curl = driver(spring)
        val book = Book(canMove = false)

        curl.drag(ProseDrag.Began(-10f), book, isRightToLeft = false)
        advanceUntilIdle()
        assertFalse(curl.isTurning)
        curl.drag(ProseDrag.Changed(-300f), book, isRightToLeft = false)
        curl.drag(ProseDrag.Ended(-300f, 0f), book, isRightToLeft = false)
        advanceUntilIdle()

        assertTrue(spring.targets.isEmpty())
        assertTrue(book.sheet!!.removed)
    }
}
