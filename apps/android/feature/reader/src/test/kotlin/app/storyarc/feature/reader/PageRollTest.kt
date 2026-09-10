package app.storyarc.feature.reader

import kotlin.math.PI
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That the page bends, and that the bend is the same bend on both platforms.
 *
 * `page-transitions`: the turning page "curves as it goes, so the reader sees a sheet
 * bending rather than a picture folding". The reader asked for it in their own words --
 * "the curl doesn't follow the finger, the page turns flat, if it's possible I'd like the
 * curl to follow the movement a bit like a magazine page turns".
 *
 * **The sample points and the expected values in [BAND] are the cross-platform contract.**
 * iOS's `PageRollTests` asserts the same table, which is how the two shaders are held to
 * one projection when neither test process has a GPU in it. Change a number here and the
 * iOS suite fails until it is changed there, which is the point.
 */
class PageRollTest {

    private val width = 1000f
    private val height = 1600f
    private val crease = 0.06f
    private val shadow = 0.05f
    private val back = 0.55f

    private fun at(x: Float, y: Float = 800f, progress: Float) = PageRoll.sample(
        x = x,
        y = y,
        width = width,
        height = height,
        progress = progress,
        crease = crease,
        shadow = shadow,
        back = back,
    )

    @Test
    fun `the radius grows from nothing, peaks halfway, and is gone by the end`() {
        assertEquals(0f, PageRoll.radius(width, 0f), 0.001f)
        assertEquals(PageRoll.R_MAX * width, PageRoll.radius(width, 0.5f), 0.001f)
        assertEquals(0f, PageRoll.radius(width, 1f), 0.01f)
        assertTrue(PageRoll.radius(width, 0.25f) < PageRoll.radius(width, 0.5f))
    }

    @Test
    fun `at rest and at the end the page is exactly the fold it replaces`() {
        // The two frames a reader sees most: a page lying flat, and a page just landed.
        // Both have to be pixel-for-pixel what they were before the roll, which is what a
        // radius of zero buys.
        val flat = at(x = 400f, progress = 0f)
        assertEquals(PageRoll.Region.FRONT, flat.region)
        assertEquals(400f, flat.material, 0.001f)
        assertEquals(1f, flat.shade, 0.001f)

        // A completed turn: the fold has reached the spine, the sheet has gone with it,
        // and what shows is the page beneath — undimmed, because the lip that cast the
        // shadow has no radius left. This is the frame the page swap replaces.
        val done = at(x = 400f, progress = 1f)
        assertEquals(PageRoll.Region.UNDER, done.region)
        assertEquals(1f, done.shade, 0.001f)
    }

    @Test
    fun `the lip stands to the right of the fold, over the page beneath`() {
        val progress = 0.5f
        val radius = PageRoll.radius(width, progress)
        val fold = PageRoll.fold(width, height, progress, y = 800f, radius = radius)

        // Just inside the fold: the top of the lip, where it is flattest and brightest.
        val top = at(x = fold + 1f, progress = progress)
        assertEquals(PageRoll.Region.LIP, top.region)
        // Halfway across the lip.
        assertEquals(PageRoll.Region.LIP, at(x = fold + radius / 2f, progress = progress).region)
        // Past the rim: the page beneath.
        assertEquals(PageRoll.Region.UNDER, at(x = fold + radius + 1f, progress = progress).region)
    }

    @Test
    fun `a point in the band is neither the flat face nor the flat back`() {
        // The pixel assertion the roll exists for. At each of the three progresses a point
        // a third of the way across the lip is sampled, and what it shows is compared with
        // what a fold would have put there: the same point mirrored, at the flat back's
        // shading. Both have to differ, because a bend both moves the texture and turns
        // the surface away from the light.
        for ((progress, expected) in BAND) {
            val radius = PageRoll.radius(width, progress)
            val fold = PageRoll.fold(width, height, progress, y = 800f, radius = radius)
            val x = fold + radius / 3f
            val sample = at(x = x, progress = progress)

            assertEquals("At $progress the point is not on the lip.", PageRoll.Region.LIP, sample.region)
            assertEquals(
                "The lip's material at $progress moved. iOS asserts this same number.",
                expected.material,
                sample.material - fold,
                0.5f,
            )
            assertEquals(
                "The lip's shading at $progress moved. iOS asserts this same number.",
                expected.shade,
                sample.shade,
                0.005f,
            )
            // And neither is what a fold would have drawn there.
            assertNotEquals(2f * fold - x, sample.material, 0.5f)
            assertNotEquals(back, sample.shade, 0.005f)
        }
    }

    @Test
    fun `the lip's shading runs from the flat back face at its top to a dark rim`() {
        val progress = 0.5f
        val radius = PageRoll.radius(width, progress)
        val fold = PageRoll.fold(width, height, progress, y = 800f, radius = radius)

        // Continuous with the flat back face at the fold, which is the seam a reader would
        // see as a hard line if it were not.
        assertEquals(back, at(x = fold, progress = progress).shade, 0.005f)
        // And edge-on at the rim, which is the page's thickness.
        assertEquals(back * PageRoll.RIM, at(x = fold + radius, progress = progress).shade, 0.005f)
    }

    @Test
    fun `the material is continuous across the seam between the lip and the flat back`() {
        val progress = 0.5f
        val radius = PageRoll.radius(width, progress)
        val fold = PageRoll.fold(width, height, progress, y = 800f, radius = radius)

        val lip = at(x = fold, progress = progress)
        val flat = at(x = fold - 0.01f, progress = progress)

        assertEquals(PageRoll.Region.LIP, lip.region)
        assertEquals(PageRoll.Region.BACK, flat.region)
        // Both are the material a half circumference along the sheet from the fold. A gap
        // here is a band of the page repeated or missing at the seam.
        assertEquals(fold + PI.toFloat() * radius, lip.material, 0.1f)
        assertEquals(fold + PI.toFloat() * radius, flat.material, 0.1f)
    }

    @Test
    fun `the silhouette across the band is not a vertical line`() {
        // The other half of what makes this a page turning rather than a wipe. Every edge
        // in the picture is the fold plus a constant, so a fold that did not lean would put
        // three vertical lines across the page.
        val progress = 0.5f
        val radius = PageRoll.radius(width, progress)

        val top = PageRoll.fold(width, height, progress, y = 0f, radius = radius)
        val middle = PageRoll.fold(width, height, progress, y = height / 2f, radius = radius)
        val bottom = PageRoll.fold(width, height, progress, y = height, radius = radius)

        assertTrue("The fold does not lean: $top at the top, $bottom at the foot.", top > bottom)
        assertEquals("The lean is even.", middle - bottom, top - middle, 0.01f)
        assertEquals(PageRoll.LEAN * radius, top - bottom, 0.01f)
    }

    @Test
    fun `the shadow's leading edge follows the rim, so it is not a vertical line either`() {
        val progress = 0.5f
        val radius = PageRoll.radius(width, progress)
        val topFold = PageRoll.fold(width, height, progress, y = 0f, radius = radius)
        val footFold = PageRoll.fold(width, height, progress, y = height, radius = radius)

        // The darkest point of the shadow is at the rim, and the rim leans with the fold.
        val atTheTop = PageRoll.sample(
            x = topFold + radius, y = 0f, width = width, height = height,
            progress = progress, crease = crease, shadow = shadow, back = back,
        )
        val atTheFoot = PageRoll.sample(
            x = footFold + radius, y = height, width = width, height = height,
            progress = progress, crease = crease, shadow = shadow, back = back,
        )
        // The same point on the screen, at the two heights: one is under the sheet and the
        // other is in open shadow, which is only true because the edge leans.
        val straightAcross = PageRoll.sample(
            x = topFold + radius, y = height, width = width, height = height,
            progress = progress, crease = crease, shadow = shadow, back = back,
        )

        assertEquals(PageRoll.Region.LIP, atTheTop.region)
        assertEquals(PageRoll.Region.LIP, atTheFoot.region)
        assertEquals(PageRoll.Region.UNDER, straightAcross.region)
    }

    @Test
    fun `the page beneath is not drawn at rest, which is how the wrong side announced itself`() {
        // ADR-0009 records the first attempt at this shader drawing the page beneath at a
        // flat page's rest. Kept as a test because the failure was invisible until a second
        // page existed, and by then it read as a decode fault rather than as a projection.
        for (x in listOf(0f, 250f, 500f, 750f, 999f)) {
            val sample = at(x = x, progress = 0f)
            assertNotEquals(
                "At rest the page beneath shows at x=$x.",
                PageRoll.Region.UNDER,
                sample.region,
            )
        }
    }

    private companion object {
        /**
         * What the lip shows a third of the way across it, at three progresses.
         *
         * The material is stated as a distance from the fold, because the fold itself moves
         * with the progress and with the lean. iOS's `PageRollTests` holds the same table.
         */
        val BAND = mapOf(
            0.25f to Expected(material = 79.25f, shade = 0.5296f),
            0.5f to Expected(material = 112.07f, shade = 0.5296f),
            0.75f to Expected(material = 79.25f, shade = 0.5296f),
        )
    }

    private data class Expected(val material: Float, val shade: Float)
}
