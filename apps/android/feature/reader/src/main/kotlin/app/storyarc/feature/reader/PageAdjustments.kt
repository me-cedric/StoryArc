package app.storyarc.feature.reader

import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.os.Build
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.asComposeRenderEffect
import app.storyarc.core.model.ImageAdjustments

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
 * Whether this device can sharpen at all.
 *
 * Sharpening is a convolution, and the only way to run one while drawing is a runtime
 * shader, which arrives in API 33. StoryArc supports 31. The control is hidden rather than
 * shown doing nothing on the two releases that cannot.
 */
internal val canSharpen: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

/**
 * A 3x3 sharpening convolution, or null when nothing was asked for.
 *
 * An unsharp mask on luminance alone, for the reason iOS uses `CISharpenLuminance`: sharpening
 * the colour channels separately fringes every line of a colour scan.
 */
internal fun ImageAdjustments.sharpeningEffect(): androidx.compose.ui.graphics.RenderEffect? {
    if (sharpness <= 0f || !canSharpen) return null
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
