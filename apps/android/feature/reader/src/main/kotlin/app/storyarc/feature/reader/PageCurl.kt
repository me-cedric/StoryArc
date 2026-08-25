package app.storyarc.feature.reader

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Matrix
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.ui.geometry.Size

/**
 * The page curl, as one AGSL shader.
 *
 * ADR-0005 and `design.md` put this here rather than in a library: Readium exposes
 * every typographic preference and no transition preference at all, so the curl is
 * ours on both platforms. `oleksandrbalan/pagecurl` is the geometry reference; this is
 * a shader rather than its `graphicsLayer` mesh, so one projection is expressed twice
 * rather than solved twice.
 *
 * ## What it draws, and what it does not
 *
 * A fold, not a roll. Seen straight down, a folded page shows two things and hides a
 * third: the part not yet reached, and the turned part lying face-down on top of it.
 * The crease is edge-on and invisible from directly above — which is why every
 * convincing 2D curl *shades* the crease rather than projecting it, and why this one
 * does too. Claiming a cylinder here would be claiming geometry that contributes no
 * pixels.
 *
 * In the direction of the turn:
 *
 *  - beyond the turned sheet's own edge: the page as it lies, not yet reached.
 *  - under the sheet: the same page mirrored about the crease and dimmed, because
 *    that is its back. A gradient along the crease is the lit leading edge.
 *  - past the crease: the page beneath, in the shadow the lifted sheet casts on it.
 *
 * The middle region sits *left* of the crease and the reveal is right of it, which is
 * the opposite of the first guess: the material that used to lie ahead of the crease
 * is what folds back over the page behind it. Getting that backwards renders the page
 * beneath at rest, which is how the mistake announced itself.
 *
 * Right-to-left is a coordinate flip rather than a second shader.
 *
 * ## Why a brush and not a `RenderEffect`
 *
 * `RenderEffect.createRuntimeShaderEffect` binds the *view's own* content to one
 * input, which is the wrong shape here: a turn needs two pages at once, and
 * `comic-reader` is explicit that a curl over a comic "uses the already-decoded page
 * directly rather than a re-raster". Two `BitmapShader`s into one `RuntimeShader`,
 * drawn as a brush, is that sentence in code.
 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
internal object PageCurl {

    /**
     * How wide the shaded crease is, as a fraction of the page's width.
     *
     * Narrow enough to read as an edge rather than as a gradient across the page, wide
     * enough to survive a low-density screen.
     */
    private const val CREASE = 0.06f

    /** How far the cast shadow reaches beyond the turned sheet, in the same units. */
    private const val SHADOW = 0.05f

    /** How much darker the back of a sheet is than its front. */
    private const val BACK = 0.55f

    private val source = """
        uniform shader page;
        uniform shader beneath;
        uniform float2 size;
        // 0 = flat, 1 = fully turned. The crease sits at (1 - progress) across.
        uniform float progress;
        uniform float crease;
        uniform float shadow;
        // 1 turns towards the left edge, -1 mirrors it for right-to-left.
        uniform float direction;
        uniform float back;

        // The page, addressed in turn-space so the caller never has to mirror.
        half4 pageAt(float turnX, float y) {
            float actual = direction > 0.0 ? turnX : size.x - turnX;
            return page.eval(float2(actual, y));
        }

        half4 main(float2 xy) {
            // One shader, two reading directions: work in a space where the turn
            // always runs towards decreasing x, and flip on the way in.
            float x = direction > 0.0 ? xy.x : size.x - xy.x;
            float fold = size.x * (1.0 - progress);

            // Where the turned sheet's own edge has reached. The material that used to
            // cover [fold, width] now covers [edge, fold], mirrored about the crease.
            float edge = 2.0 * fold - size.x;

            // Not yet reached by the sheet: the page as it lies.
            if (x < edge) {
                return pageAt(x, xy.y);
            }

            // Under the turned sheet. It is above the page, so it wins.
            if (x <= fold) {
                half4 face = pageAt(2.0 * fold - x, xy.y);

                // The back of a page is not its front: paper is not transparent, and a
                // mirrored image at full brightness reads as a reflection rather than
                // as a turned leaf.
                half3 dimmed = face.rgb * half(back);

                // The lit crease: brightest at the fold, gone within `crease`.
                float toFold = (fold - x) / (size.x * crease);
                half lit = half(exp(-toFold * toFold) * 0.5);

                return half4(saturate(dimmed + lit), face.a);
            }

            // Lifted away from here, so the page beneath shows. Darkest against the
            // crease, which is the only place a lifted page can cast a shadow.
            float away = (x - fold) / (size.x * shadow);
            half dark = half(1.0 - 0.45 * exp(-away * away));
            half4 under = beneath.eval(xy);
            return half4(under.rgb * dark, under.a);
        }
    """.trimIndent()

    /**
     * One frame of a turn, as a brush over the whole page area.
     *
     * @param progress 0 while the page is flat, 1 when it has fully turned.
     * @param isRightToLeft mirrors the crease's origin, and the gesture with it.
     * @param beneath the page being revealed. The outgoing page is reused when there
     *   is none, so the last page still turns rather than tearing to nothing — the
     *   boundary is the caller's business, not the shader's.
     */
    fun shader(
        area: Size,
        progress: Float,
        isRightToLeft: Boolean,
        page: Bitmap,
        beneath: Bitmap?,
    ): Shader = RuntimeShader(source).apply {
        setFloatUniform("size", area.width, area.height)
        setFloatUniform("progress", progress.coerceIn(0f, 1f))
        setFloatUniform("crease", CREASE)
        setFloatUniform("shadow", SHADOW)
        setFloatUniform("direction", if (isRightToLeft) -1f else 1f)
        setFloatUniform("back", BACK)
        setInputShader("page", page.fitted(area))
        setInputShader("beneath", (beneath ?: page).fitted(area))
    }

    /**
     * The bitmap as a shader scaled to fit the area, centred.
     *
     * `Fit` rather than fill, for the reason the reader fits pages that way: cropping a
     * comic page loses artwork.
     *
     * `DECAL` rather than `CLAMP`: outside the page there is nothing, and clamping
     * smeared the edge pixel across the letterbox instead of leaving the black the
     * other three modes show there.
     */
    private fun Bitmap.fitted(area: Size): Shader {
        val scale = minOf(area.width / width, area.height / height)
        val matrix = Matrix().apply {
            setScale(scale, scale)
            postTranslate(
                (area.width - width * scale) / 2f,
                (area.height - height * scale) / 2f,
            )
        }
        return BitmapShader(this, Shader.TileMode.DECAL, Shader.TileMode.DECAL).apply {
            setLocalMatrix(matrix)
        }
    }
}
