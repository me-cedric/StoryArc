package app.storyarc.feature.epubreader

import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Curl reads every phase of the finger, so the fold can follow it. Task 8.12.
 *
 * Robolectric, because the rule under test is Android's touch dispatch: a parent that
 * intercepts a drag past the slop and is then handed the rest of it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class TurnInterceptorDragTest {

    private val drags = mutableListOf<ProseDrag>()
    private val swipes = mutableListOf<Boolean>()

    private val interceptor = TurnInterceptor(ApplicationProvider.getApplicationContext()).apply {
        // Clickable, as the web view is: it takes the press, so the drag reaches this view
        // through the intercept, which is the path a reader's finger takes.
        addView(View(context).apply { isClickable = true }, ViewGroup.LayoutParams(1000, 2000))
        measure(
            View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(2000, View.MeasureSpec.EXACTLY),
        )
        layout(0, 0, 1000, 2000)
    }

    private fun touch(action: Int, x: Float, y: Float = 500f, time: Long = 0) {
        val event = MotionEvent.obtain(0, time, action, x, y, 0)
        interceptor.dispatchTouchEvent(event)
        event.recycle()
    }

    private fun sweep(from: Float, to: Float, y: (Float) -> Float = { 500f }) {
        touch(MotionEvent.ACTION_DOWN, from, y(from))
        val steps = 10
        for (step in 1..steps) {
            val x = from + (to - from) * step / steps
            touch(MotionEvent.ACTION_MOVE, x, y(x), time = step * 10L)
        }
        touch(MotionEvent.ACTION_UP, to, y(to), time = (steps + 1) * 10L)
    }

    @Test
    fun `under Curl a sideways drag reports its start, every move and its release`() {
        interceptor.onTurn = { swipes += it }
        interceptor.onDrag = { drags += it }

        sweep(from = 800f, to = 300f)

        assertTrue(drags.first() is ProseDrag.Began)
        assertTrue(drags.drop(1).dropLast(1).all { it is ProseDrag.Changed })
        val last = drags.last()
        assertTrue(last is ProseDrag.Ended)
        assertEquals(-500f, (last as ProseDrag.Ended).travel, 0.5f)
        // The release is the curl's to read, so the Fast fade swipe does not also turn a page.
        assertTrue(swipes.isEmpty())
    }

    @Test
    fun `a cancelled drag lets go of the page like a finger that lifted`() {
        interceptor.onTurn = { swipes += it }
        interceptor.onDrag = { drags += it }

        touch(MotionEvent.ACTION_DOWN, 800f)
        touch(MotionEvent.ACTION_MOVE, 700f, time = 10)
        touch(MotionEvent.ACTION_MOVE, 600f, time = 20)
        touch(MotionEvent.ACTION_CANCEL, 600f, time = 30)

        assertTrue(drags.last() is ProseDrag.Ended)
    }

    @Test
    fun `a finger going down the page lifts nothing`() {
        interceptor.onTurn = { swipes += it }
        interceptor.onDrag = { drags += it }

        sweep(from = 500f, to = 560f) { x -> 500f + (x - 500f) * 10f }

        assertTrue(drags.isEmpty())
    }

    @Test
    fun `under Fast fade the release alone turns the page`() {
        interceptor.onTurn = { swipes += it }

        sweep(from = 800f, to = 300f)

        assertEquals(listOf(true), swipes)
        assertTrue(drags.isEmpty())
    }
}
