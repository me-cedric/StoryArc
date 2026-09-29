package app.storyarc.feature.reader

import android.graphics.Bitmap
import android.graphics.Color
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The CPU unsharp mask (D9) that draws sharpening on API 31 and 32, where there is no
 * runtime shader to draw it live. iOS offers sharpness on every version already; this
 * is the fallback that lets Android do the same.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PageAdjustmentsTest {

    private fun gray(value: Int, alpha: Int = 255) = Color.argb(alpha, value, value, value)

    @Test
    fun `a uniform region is unchanged by sharpening`() {
        val pixel = gray(128)
        assertEquals(pixel, sharpenedPixel(pixel, neighbourSum = 128f * 4, amount = 1f))
    }

    @Test
    fun `a value that would go negative clamps to black rather than below it`() {
        val pixel = gray(50)
        // Four much brighter neighbours pull the sharpened luma below zero.
        assertEquals(gray(0), sharpenedPixel(pixel, neighbourSum = 75f * 4, amount = 1f))
    }

    @Test
    fun `a value pulled far past white clamps to the ratio's own ceiling`() {
        val pixel = gray(10)
        // Four much darker neighbours (zero) push the ratio past what is kept.
        assertEquals(gray(30), sharpenedPixel(pixel, neighbourSum = 0f, amount = 1f))
    }

    @Test
    fun `zero amount leaves the pixel exactly as it was`() {
        val pixel = gray(90)
        assertEquals(pixel, sharpenedPixel(pixel, neighbourSum = 40f * 4, amount = 0f))
    }

    @Test
    fun `alpha survives untouched, whatever the sharpening does to the colour`() {
        val pixel = gray(50, alpha = 128)
        val sharpened = sharpenedPixel(pixel, neighbourSum = 75f * 4, amount = 1f)
        assertEquals(128, Color.alpha(sharpened))
    }

    @Test
    fun `sharpening at zero amount returns the very same bitmap`() {
        val bitmap = Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888)
        assertSame(bitmap, runBlocking { bitmap.sharpened(0f) })
    }

    @Test
    fun `a real bitmap sharpens pixel by pixel through the same rule`() {
        val bitmap = Bitmap.createBitmap(3, 3, Bitmap.Config.ARGB_8888)
        for (y in 0 until 3) {
            for (x in 0 until 3) {
                // A bright dot in an otherwise dark 3x3 page.
                bitmap.setPixel(x, y, if (x == 1 && y == 1) gray(200) else gray(50))
            }
        }

        val sharpened = runBlocking { bitmap.sharpened(1f) }

        // The centre pixel's four neighbours are all the dark value, so it sharpens
        // brighter still — the whole point of the mask.
        assertEquals(255, Color.red(sharpened.getPixel(1, 1)))
        // A corner has no orthogonal neighbour past the edge, so it repeats its own —
        // `maxOf`/`minOf` clamping means a uniform corner is unchanged.
        assertEquals(gray(50), sharpened.getPixel(0, 0))
    }

    @Test
    fun `a pass whose value the slider has already left stops rather than finishing`() {
        // A drag restarts the pass for every value it moves through. A pass that ran to
        // the end regardless kept a full page's convolution going for each of them.
        val bitmap = Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888)
        var outcome: Result<Bitmap>? = null
        runBlocking {
            launch {
                coroutineContext.job.cancel()
                outcome = runCatching { bitmap.sharpened(1f) }
            }.join()
        }
        assertTrue(outcome?.exceptionOrNull() is CancellationException)
    }
}
