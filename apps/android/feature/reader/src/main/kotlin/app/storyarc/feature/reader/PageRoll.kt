package app.storyarc.feature.reader

import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin

/**
 * Where a rolling page's surface is, and how the light falls on it.
 *
 * **The projection, in arithmetic, so it can be asserted.** `PageCurl`'s AGSL and iOS's
 * `PageCurl.metal` are transliterations of what is here, and `PageRollTest` and
 * `PageRollTests` assert this against the same table of expected values on both platforms —
 * which is how `design.md`'s "one projection expressed twice rather than solved twice" is
 * held to when no test process has a GPU in it. The constants reach both shaders as
 * uniforms read from this object, so a number cannot drift; only the formula can, and
 * `PageCurlShaderTest` is the guard on that.
 *
 * **The model.** The sheet lies flat to the fold, wraps a cylinder of radius [radius]
 * whose lower tangent is the fold, and comes back over itself lying flat. So the lip
 * bulges to the *right* of the fold, over the page beneath, and the flat back face runs
 * leftwards from it -- which is where a real page's thickness shows, and what ADR-0009's
 * crease of no radius could not draw. Four regions across the width, at each height:
 *
 * 1. the page's own front face, out to the sheet's free edge;
 * 2. the flat back face, from that edge to the fold;
 * 3. the lip, from the fold to the rim a radius further right;
 * 4. the page beneath, with the lip's shadow cast on it.
 *
 * **The fold leans**, by [LEAN] radii over the height, so the bottom corner runs ahead of
 * the top one. Without it every edge in the picture is a vertical line, which is the
 * difference between a page turning and a wipe. It is a lean and not a cone: a cone needs
 * a second radius and a pivot, and the pivot's own arithmetic is not something a reader can
 * see in a 400 ms turn.
 *
 * At `progress` 0 and 1 the radius is zero, every region collapses to the fold this
 * replaces, and the ends of a turn are pixel-for-pixel what they were.
 */
internal object PageRoll {

    /** The lip's radius at its widest, as a fraction of the page's width. */
    const val R_MAX = 0.04f

    /** How far the fold leans over the page's height, in radii. */
    const val LEAN = 1.5f

    /** How much of the lip's brightness survives at the rim, where it is edge-on. */
    const val RIM = 0.35f

    /** Which surface a point on the screen shows. */
    internal enum class Region { FRONT, BACK, LIP, UNDER }

    /**
     * What to draw at one point.
     *
     * @property material where on the page the surface at this point came from, in
     *   turn-space x. Meaningless for [Region.UNDER], which samples the page beneath at
     *   the screen point itself.
     * @property shade what to multiply the sampled colour by: 1 for the front face, less
     *   for a back face turned away from the light, and the shadow's own factor under the
     *   lip.
     * @property lit what to add afterwards, which is the sheen along the top of the lip.
     */
    internal data class Sample(
        val region: Region,
        val material: Float,
        val shade: Float,
        val lit: Float,
    )

    /**
     * The lip's radius at this progress.
     *
     * A sine, so the roll grows from nothing, is at its fullest halfway through the turn,
     * and is back to nothing when the page lands. The ends matter more than the middle:
     * a radius that did not vanish would leave a lip standing on a page at rest.
     */
    fun radius(width: Float, progress: Float): Float =
        // Floored at zero because `sin` of a float pi is a hair *below* zero, and a
        // negative radius puts the rim to the left of the fold -- so a page that had just
        // landed drew the page beneath across itself. Found by the test below.
        (R_MAX * width * sin(PI.toFloat() * progress.coerceIn(0f, 1f))).coerceAtLeast(0f)

    /** Where the sheet leaves the page at this height. */
    fun fold(width: Float, height: Float, progress: Float, y: Float, radius: Float): Float {
        val flat = width * (1f - progress.coerceIn(0f, 1f))
        if (height <= 0f) return flat
        return flat + LEAN * radius * (0.5f - y / height)
    }

    /**
     * What the screen shows at ([x], [y]).
     *
     * @param crease how far the sheen reaches from the fold, as a fraction of the width.
     * @param shadow how far the lip's shadow reaches, as a fraction of the width.
     * @param back how much light the flat back face keeps.
     */
    @Suppress("LongParameterList")
    fun sample(
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        progress: Float,
        crease: Float,
        shadow: Float,
        back: Float,
    ): Sample {
        val radius = radius(width, progress)
        val fold = fold(width, height, progress, y, radius)
        val rim = fold + radius
        val sheen = { distance: Float ->
            val reach = distance / (width * crease)
            exp(-reach * reach) * 0.5f
        }

        if (x > rim) {
            val away = (x - rim) / (width * shadow)
            return Sample(Region.UNDER, material = x, shade = 1f - 0.45f * exp(-away * away), lit = 0f)
        }

        if (radius > 0f && x >= fold) {
            // The visible half of the cylinder is the upper one, so the angle runs back
            // from a half turn at the fold to a quarter turn at the rim. Arc length is
            // what the sheet spends getting there, and arc length is where the texture
            // came from -- which is the whole of the remapping the fold had none of.
            val across = ((x - fold) / radius).coerceIn(0f, 1f)
            val angle = PI.toFloat() - asin(across)
            val lambert = -cos(angle)
            return Sample(
                region = Region.LIP,
                material = fold + radius * angle,
                shade = back * (RIM + (1f - RIM) * lambert),
                lit = sheen(x - fold),
            )
        }

        // The flat back face, shifted by the half circumference the lip spent bending.
        val edge = 2f * fold - width + PI.toFloat() * radius
        if (x < edge) return Sample(Region.FRONT, material = x, shade = 1f, lit = 0f)
        return Sample(
            region = Region.BACK,
            material = 2f * fold - x + PI.toFloat() * radius,
            shade = back,
            lit = sheen(fold - x),
        )
    }
}
