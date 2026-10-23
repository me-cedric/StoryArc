package app.storyarc.core.designsystem.cover

import android.graphics.Bitmap
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A server cover is decoded no larger than the cell it fills. Four cells decoded every
 * cover at full size on the main dispatcher; this is the decoder they share.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class RemoteCoverTest {

    @Test
    fun `the step is the largest power of two that keeps the longer side at the cell size`() {
        assertEquals(1, sampleSize(longerSide = 300, maxPixelSize = 200))
        assertEquals(2, sampleSize(longerSide = 400, maxPixelSize = 200))
        assertEquals(4, sampleSize(longerSide = 1600, maxPixelSize = 300))
        assertEquals(1, sampleSize(longerSide = 100, maxPixelSize = 0))
    }

    @Test
    fun `a picture larger than the cell comes back sampled, never below the cell`() {
        val decoded = decodeSampled(png(width = 400, height = 600), maxPixelSize = 200)
        assertNotNull(decoded)
        assertEquals(300, decoded!!.height)
        assertEquals(200, decoded.width)
    }

    @Test
    fun `a picture that already fits is decoded as it is`() {
        val decoded = decodeSampled(png(width = 40, height = 60), maxPixelSize = 200)
        assertEquals(60, decoded?.height)
    }

    @Test
    fun `bytes that are not a picture are null rather than a throw`() {
        assertNull(decodeSampled(ByteArray(0), maxPixelSize = 200))
        assertNull(decodeSampled("not a picture".toByteArray(), maxPixelSize = 200))
    }

    private fun png(width: Int, height: Int): ByteArray = ByteArrayOutputStream().use { out ->
        Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            .compress(Bitmap.CompressFormat.PNG, 100, out)
        out.toByteArray()
    }
}
