package app.storyarc.core.format

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import java.nio.ByteBuffer
import kotlin.math.roundToInt

/**
 * Decoding a page's bytes into something drawable.
 *
 * ADR-0005 chose the platform decoder rather than a library: `ImageDecoder` here,
 * ImageIO on Apple. Between them they cover the only three things the reader
 * needs — decode from bytes, downsample to a target size, and re-decode larger
 * when the user zooms — and keeping both platforms on their own system decoder
 * keeps the two paths structurally alike.
 *
 * iOS's `PageDecoder` mirrors this file.
 */
/**
 * A page's pixel dimensions.
 *
 * Deliberately not `android.util.Size`: that is a framework class and a stub in
 * JVM unit tests, which would push pure arithmetic onto a device for no reason.
 * It also keeps the format layer free of Android UI types.
 */
data class PageSize(val width: Int, val height: Int)

object PageDecoder {
    class UnrecognisedImageException : Exception("bytes are not a recognised image")

    /**
     * A page's pixel dimensions, read from the image header without decoding it.
     *
     * `inJustDecodeBounds` reads the header and allocates no pixels, which is
     * what makes this cheap enough to call while indexing thousands of pages.
     * `comic-reader` needs it to detect double-page spreads and to size a
     * placeholder at the correct aspect ratio before the page itself arrives.
     */
    fun dimensions(data: ByteArray): PageSize {
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(data, 0, data.size, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) throw UnrecognisedImageException()
        return PageSize(options.outWidth, options.outHeight)
    }

    /**
     * Decodes at most [maxPixelSize] on the longest edge, or at full size when
     * null.
     *
     * Passing the display's need rather than null is the difference between a
     * 2000x3000 page costing 24 MB of pixels and costing what it is shown at —
     * which is what `publication-formats` means by downsampling a page too large
     * for the device.
     */
    fun decode(data: ByteArray, maxPixelSize: Int? = null): Bitmap {
        val source = ImageDecoder.createSource(ByteBuffer.wrap(data))
        return try {
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                // Software allocation so the result is a readable Bitmap rather
                // than a hardware one the tests and the zoom path cannot inspect.
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                if (maxPixelSize != null) {
                    val target = targetSize(info.size.width, info.size.height, maxPixelSize)
                    decoder.setTargetSize(target.width, target.height)
                }
            }
        } catch (_: ImageDecoder.DecodeException) {
            throw UnrecognisedImageException()
        }
    }

    /**
     * The size that bounds the longest edge to [maxPixelSize] while preserving
     * the aspect ratio. Never upscales: asking for more than the source has
     * returns the source's own size.
     *
     * Pure arithmetic, so it is unit-testable on the JVM without a device —
     * which is the whole reason it is a separate function.
     */
    fun targetSize(width: Int, height: Int, maxPixelSize: Int): PageSize {
        val longest = maxOf(width, height)
        if (longest <= maxPixelSize || longest == 0) return PageSize(width, height)
        val scale = maxPixelSize.toDouble() / longest.toDouble()
        return PageSize(
            (width * scale).roundToInt().coerceAtLeast(1),
            (height * scale).roundToInt().coerceAtLeast(1),
        )
    }

    /**
     * Whether a page is a double-page spread.
     *
     * `comic-reader` requires a materially wider-than-tall page in a portrait
     * publication to be shown alone rather than split across two turns. The
     * threshold is deliberately generous: a page that is merely a little wide is
     * not a spread, and guessing wrong is worse than not guessing.
     */
    fun isSpread(width: Int, height: Int, threshold: Double = 1.2): Boolean {
        if (height <= 0) return false
        return width.toDouble() / height.toDouble() >= threshold
    }
}
