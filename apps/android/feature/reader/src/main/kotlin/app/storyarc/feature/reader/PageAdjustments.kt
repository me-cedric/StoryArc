package app.storyarc.feature.reader

import android.graphics.Bitmap
import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.os.Build
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.asComposeRenderEffect
import app.storyarc.core.model.BorderCrop
import app.storyarc.core.model.ImageAdjustments
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlin.math.roundToInt

/**
 * The colour part of an adjustment, as the one matrix a renderer takes.
 *
 * `comic-reader` wants brightness, contrast, colour inversion and greyscale "with a live
 * preview". All four are per-pixel colour operations, so all four compose into a single
 * 4x5 matrix the GPU applies while drawing: no bitmap is copied and no decode is repeated,
 * and dragging a slider costs a redraw.
 *
 * Null when nothing was asked for. A neutral filter still costs a pass over every page of
 * every comic, which is most of the time.
 */
internal fun ImageAdjustments.colourFilter(): ColorFilter? {
    if (isNeutral) return null

    val matrix = ColorMatrix()
    if (isGreyscale) matrix.setToSaturation(0f)

    // Contrast pivots on mid-grey rather than on black, so raising it darkens the shadows
    // and lightens the highlights instead of washing the whole page towards white.
    val contrast = contrastFactor
    val pivot = 255f * (1f - contrast) / 2f
    // Brightness is an offset in the same 0..255 the matrix works in.
    val offset = pivot + brightness * 255f
    matrix *= ColorMatrix(
        floatArrayOf(
            contrast, 0f, 0f, 0f, offset,
            0f, contrast, 0f, 0f, offset,
            0f, 0f, contrast, 0f, offset,
            0f, 0f, 0f, 1f, 0f,
        ),
    )

    if (isInverted) {
        // Last, so the reader's brightness and contrast are what they see rather than their
        // opposites: inverting first would send a brightened page darker.
        matrix *= ColorMatrix(
            floatArrayOf(
                -1f, 0f, 0f, 0f, 255f,
                0f, -1f, 0f, 0f, 255f,
                0f, 0f, -1f, 0f, 255f,
                0f, 0f, 0f, 1f, 0f,
            ),
        )
    }

    return ColorFilter.colorMatrix(matrix)
}

/**
 * The same page with its uniform margin gone, or the same page when there was none.
 *
 * `comic-reader`: "uniform white or black margins are detected and trimmed per page". Per
 * page is the requirement and also the only thing that works -- a scan's margin varies from
 * sheet to sheet, and one inset applied to a whole comic crops half of it wrongly.
 *
 * The detection reads a thumbnail rather than the page. A margin is uniform by definition, so
 * it survives being scaled down, and reading two million pixels on every page turn is the
 * difference between a reader who notices and one who does not.
 */
internal fun Bitmap.cropped(isEnabled: Boolean): Bitmap {
    if (!isEnabled) return this
    val small = thumbnail() ?: return this
    val pixels = IntArray(small.width * small.height)
    small.getPixels(pixels, 0, small.width, 0, 0, small.width, small.height)

    val inset = BorderCrop.inset(small.width, small.height) { x, y ->
        // The red channel alone. A margin is grey by definition -- white or black -- so the
        // other two say the same thing, and asking for one is a third of the work.
        (pixels[y * small.width + x] shr 16) and 0xFF
    }
    if (small !== this) small.recycle()
    if (inset.isEmpty) return this

    // Back up to the page's own scale, which is what the crop has to be expressed in.
    val scale = width.toFloat() / small.width
    val left = (inset.left * scale).toInt()
    val top = (inset.top * scale).toInt()
    val cropWidth = width - left - (inset.right * scale).toInt()
    val cropHeight = height - top - (inset.bottom * scale).toInt()
    if (cropWidth <= 0 || cropHeight <= 0) return this
    return Bitmap.createBitmap(this, left, top, cropWidth, cropHeight)
}

/** A small copy, small enough that reading every pixel of it costs nothing. */
private fun Bitmap.thumbnail(): Bitmap? {
    val side = 256
    if (maxOf(width, height) <= side) return this
    val scale = side.toFloat() / maxOf(width, height)
    return runCatching {
        Bitmap.createScaledBitmap(
            this,
            maxOf(1, (width * scale).toInt()),
            maxOf(1, (height * scale).toInt()),
            false,
        )
    }.getOrNull()
}

/**
 * Whether this device can draw sharpening live, while the page is composed.
 *
 * A runtime shader is the only way to run the convolution *while drawing*, and it
 * arrives in API 33. Below that, `Bitmap.sharpened` runs the same convolution on the
 * decoded page instead (D9) — slower, and once per page rather than once per frame,
 * which is why it is not the answer on every version.
 */
internal val canSharpenWithShader: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

/**
 * A 3x3 sharpening convolution, or null when nothing was asked for.
 *
 * An unsharp mask on luminance alone, for the reason iOS uses `CISharpenLuminance`: sharpening
 * the colour channels separately fringes every line of a colour scan.
 */
internal fun ImageAdjustments.sharpeningEffect(): androidx.compose.ui.graphics.RenderEffect? {
    if (sharpness <= 0f || !canSharpenWithShader) return null
    val shader = RuntimeShader(SHARPEN_SHADER)
    // 0..1 covers "slightly crisper" to "as far as this is worth taking". Past that the
    // filter finds noise rather than lines.
    shader.setFloatUniform("amount", sharpness)
    return RenderEffect
        .createRuntimeShaderEffect(shader, "page")
        .asComposeRenderEffect()
}

/**
 * Luminance-only unsharp mask.
 *
 * The centre tap is weighted up and the four neighbours down, which is the smallest kernel
 * that recovers an edge. The result is mixed back by `amount` so the slider's left end is
 * genuinely the original rather than a slightly-different original.
 */
private val SHARPEN_SHADER = """
    uniform shader page;
    uniform float amount;

    half4 main(float2 coord) {
        half4 here = page.eval(coord);
        half4 sum =
            page.eval(coord + float2(-1.0,  0.0)) +
            page.eval(coord + float2( 1.0,  0.0)) +
            page.eval(coord + float2( 0.0, -1.0)) +
            page.eval(coord + float2( 0.0,  1.0));
        half4 sharp = here * 5.0 - sum;
        half4 mixed = mix(here, sharp, amount);
        return half4(clamp(mixed.rgb, 0.0, 1.0), here.a);
    }
""".trimIndent()

/**
 * The same unsharp mask [sharpeningEffect] draws with a shader, computed on the CPU
 * instead — API 31 and 32 have no runtime shader to draw it with (D9).
 *
 * Luminance-only, the same reason the shader is: sharpening each colour channel on its
 * own fringes every line of a colour scan. Each pixel's own channels are scaled by how
 * much its luminance moved, rather than sharpened separately.
 *
 * ponytail: a plain per-pixel loop, not a native or `RenderScript` pass — this is the
 * one CPU path in the app that touches every pixel of a full-resolution page, so it
 * belongs off the main thread (the caller's job) rather than optimised further until a
 * profile says so.
 */
internal suspend fun Bitmap.sharpened(amount: Float): Bitmap {
    if (amount <= 0f) return this
    val w = width
    val h = height
    val pixels = IntArray(w * h)
    getPixels(pixels, 0, w, 0, 0, w, h)
    val out = IntArray(w * h)
    for (y in 0 until h) {
        // Once a row: a slider drag cancels the pass for each value it leaves behind,
        // and a pass that ignored that would keep a full page's convolution running
        // for every one of them at once.
        currentCoroutineContext().ensureActive()
        for (x in 0 until w) {
            val here = pixels[y * w + x]
            val left = pixels[y * w + maxOf(x - 1, 0)]
            val right = pixels[y * w + minOf(x + 1, w - 1)]
            val up = pixels[maxOf(y - 1, 0) * w + x]
            val down = pixels[minOf(y + 1, h - 1) * w + x]
            out[y * w + x] = sharpenedPixel(here, neighbourSum = luma(left) + luma(right) + luma(up) + luma(down), amount)
        }
    }
    return Bitmap.createBitmap(out, w, h, Bitmap.Config.ARGB_8888)
}

private fun luma(pixel: Int): Float {
    val r = (pixel shr 16) and 0xFF
    val g = (pixel shr 8) and 0xFF
    val b = pixel and 0xFF
    return 0.299f * r + 0.587f * g + 0.114f * b
}

/** One pixel of [Bitmap.sharpened]'s convolution, isolated so `PageAdjustmentsTest` can
 * drive it with plain numbers instead of a whole bitmap. */
internal fun sharpenedPixel(pixel: Int, neighbourSum: Float, amount: Float): Int {
    val here = luma(pixel)
    val sharp = here * 5f - neighbourSum
    val mixed = here + (sharp - here) * amount
    val ratio = if (here > 0f) (mixed / here).coerceIn(0f, 3f) else 1f
    val a = (pixel shr 24) and 0xFF
    val r = (((pixel shr 16) and 0xFF) * ratio).roundToInt().coerceIn(0, 255)
    val g = (((pixel shr 8) and 0xFF) * ratio).roundToInt().coerceIn(0, 255)
    val b = ((pixel and 0xFF) * ratio).roundToInt().coerceIn(0, 255)
    return (a shl 24) or (r shl 16) or (g shl 8) or b
}
