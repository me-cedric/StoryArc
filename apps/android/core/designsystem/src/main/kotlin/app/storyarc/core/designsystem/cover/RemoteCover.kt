package app.storyarc.core.designsystem.cover

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * A server's cover for one cell: fetched once per [key], decoded off the main thread, and
 * no larger than it is drawn.
 *
 * [load] answers the bytes, through whichever client holds the credential — an image loader
 * has nowhere to put one. Null or a throw from it, or bytes that are not a picture, leave
 * the cell empty, which is a normal state rather than a failure. [maxPixelSize] is the
 * longer side of the cell in pixels; see [decodeSampled].
 */
@Composable
fun rememberRemoteCover(key: Any?, maxPixelSize: Int, load: suspend () -> ByteArray?): Bitmap? {
    var cover by remember(key) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(key) {
        val bytes = runCatching { load() }.getOrNull() ?: return@LaunchedEffect
        cover = withContext(Dispatchers.IO) { decodeSampled(bytes, maxPixelSize) }
    }
    return cover
}

/**
 * [bytes] decoded at the power-of-two step that keeps the longer side at least
 * [maxPixelSize], or null when they are not a picture this device can decode.
 *
 * The step only ever shrinks, and stops while the picture is still at least the size it
 * is drawn at, so a 2000 by 3000 server cover costs what a 168 dp cell shows rather than
 * 24 MB of pixels per cell.
 */
fun decodeSampled(bytes: ByteArray, maxPixelSize: Int): Bitmap? = runCatching {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    val options = BitmapFactory.Options().apply {
        inSampleSize = sampleSize(maxOf(bounds.outWidth, bounds.outHeight), maxPixelSize)
    }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
}.getOrNull()

/** The largest power of two that leaves [longerSide] / sample at least [maxPixelSize]. */
internal fun sampleSize(longerSide: Int, maxPixelSize: Int): Int {
    var sample = 1
    while (maxPixelSize > 0 && longerSide / (sample * 2) >= maxPixelSize) sample *= 2
    return sample
}
