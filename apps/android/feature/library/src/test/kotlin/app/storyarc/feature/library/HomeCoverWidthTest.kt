package app.storyarc.feature.library

import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Every cover on Home follows the reader's text size — the plain shelves and the hero both.
 *
 * Neither did. `coverMinimumWidth` took the font scale as an optional argument and
 * [homeShelfCoverWidth] omitted it, so at an accessibility text size the library grid on the
 * next destination widened 104 → 146 dp while Home's Up next, Recently added and Finished
 * runs stayed at the ordinary width. [homeHeroWidth] — the Keep reading card, which is the
 * largest thing on the surface — read the window alone and did not step at all. Two
 * hardcoded ladders on one screen, neither of them reading the setting. This asserts the
 * arithmetic both fixes are for.
 */
class HomeCoverWidthTest {

    /** `design.md` §4's three tiers, each a quarter wider because a shelf shows six covers. */
    @Test
    fun `a home cover is the grid's tier, scaled`() {
        assertEquals(130.dp, homeShelfCoverWidth(windowWidthDp = 360, fontScale = 1f))
        assertEquals(165.dp, homeShelfCoverWidth(windowWidthDp = 600, fontScale = 1f))
        assertEquals(197.5.dp, homeShelfCoverWidth(windowWidthDp = 840, fontScale = 1f))
    }

    /**
     * And it takes the accessibility step with the grid. 146 is `coverMinimumWidth`'s stepped
     * phone tier; anything still at 130 here means the font scale never reached the ladder.
     */
    @Test
    fun `a home cover takes the accessibility step`() {
        assertEquals(182.5.dp, homeShelfCoverWidth(windowWidthDp = 360, fontScale = 1.5f))
        assertEquals(231.25.dp, homeShelfCoverWidth(windowWidthDp = 600, fontScale = 1.5f))
        assertEquals(276.25.dp, homeShelfCoverWidth(windowWidthDp = 840, fontScale = 1.5f))
    }

    /**
     * The boundary itself: 1.3 is where Android's ordinary Font size slider stops, so it is
     * the first scale that steps. A cover the same width either side of it is a shelf that
     * reads the setting and ignores it.
     */
    @Test
    fun `the step lands on the accessibility boundary and not before`() {
        assertEquals(130.dp, homeShelfCoverWidth(windowWidthDp = 360, fontScale = 1.29f))
        assertEquals(182.5.dp, homeShelfCoverWidth(windowWidthDp = 360, fontScale = 1.3f))
    }

    /**
     * A window tall enough that the height cap is inert.
     *
     * The hero is the smaller of what the width offers and what the height can afford, and
     * these cases are about the width. A short window is its own test, below.
     */
    private val tall = 2000

    /** The hero's three widths: a share of a phone, a tier on anything larger. */
    @Test
    fun `about one and a half cards fit across a phone`() {
        // `home-screen`: "about one and a half cards fit across a phone, so the second is
        // plainly a second and not a thumbnail beside a hero". A 360 dp phone has 320 dp
        // between its gutters, and a card is two thirds of it.
        val phone = homeHeroWidth(windowWidthDp = 360, windowHeightDp = tall, fontScale = 1f)

        assertEquals(320.dp / 1.5f, phone)
        // Which is what "one and a half" means, read back: the room divided by the card.
        assertEquals(1.5f, 320f / phone.value, 0.01f)
    }

    @Test
    fun `a larger window keeps its tiers, because a card there is not a share of the screen`() {
        assertEquals(240.dp, homeHeroWidth(windowWidthDp = 600, windowHeightDp = tall, fontScale = 1f))
        assertEquals(280.dp, homeHeroWidth(windowWidthDp = 840, windowHeightDp = tall, fontScale = 1f))
    }

    /**
     * And the hero steps too. This is the assertion that change existed for: the Keep
     * reading card is the largest thing on Home, and it was the one surface here with no
     * accessibility step at all.
     */
    @Test
    fun `the hero takes the same accessibility step`() {
        assertEquals(336.dp, homeHeroWidth(windowWidthDp = 600, windowHeightDp = tall, fontScale = 1.5f))
        assertEquals(392.dp, homeHeroWidth(windowWidthDp = 840, windowHeightDp = tall, fontScale = 1.5f))
    }

    /**
     * The card never asks for more room than it is given, in either direction.
     *
     * A 300 dp window — a freeform slot, a folded inner display, a phone in a small split —
     * has 260 dp between its gutters, and the stepped tier would overflow it.
     */
    @Test
    fun `the hero never asks for more room than the window leaves it`() {
        // Asserted as the invariant rather than at one window, because the phone tier is
        // now a share of the room and can no longer exceed it by construction -- so a
        // single case would be asserting arithmetic that cannot fail. What can still fail
        // is a *fixed* tier in a narrow window, which is why the sweep includes both.
        for (width in listOf(240, 300, 360, 411, 600, 840, 1280)) {
            for (scale in listOf(1f, 1.3f, 1.5f, 2f)) {
                val room = width.dp - StoryArcSpace.gutter * 2
                val hero = homeHeroWidth(width, tall, scale)
                assertTrue(
                    "A ${width}dp window at scale $scale leaves $room and the hero took $hero.",
                    hero <= room,
                )
            }
        }
    }

    /**
     * And capped by the height, which is the half that stops the bigger card costing the
     * reader the next heading.
     *
     * `home-screen` asks for both at once — one and a half cards across, and the next
     * section's heading visible without scrolling — and on a short phone they disagree.
     * The height wins: a reader can scroll to see a second card, and cannot scroll to
     * discover that a surface continues. `HomeHeroHeightTest` is where the fold is
     * asserted; this is only that the cap bites.
     */
    @Test
    fun `a window too short for the rule still gets a card, and not a negative one`() {
        // The crash this replaces: a landscape phone has less room above the fold than the
        // chrome and the next heading want, so the width the height "affords" is negative,
        // and `HorizontalUncontainedCarousel` threw `IndexOutOfBoundsException: Index -1`
        // on it. Every unit test passed; rotating the phone found it.
        val landscape = homeHeroWidth(windowWidthDp = 891, windowHeightDp = 411, fontScale = 1f)

        assertTrue("A landscape phone was given a \$landscape card.", landscape > 0.dp)
    }

    @Test
    fun `no window of any shape asks for a card of no width`() {
        for (width in listOf(0, 240, 300, 360, 411, 600, 891, 1280)) {
            for (height in listOf(0, 200, 320, 411, 640, 800, 914, 1280)) {
                for (scale in listOf(1f, 1.3f, 2f)) {
                    val hero = homeHeroWidth(width, height, scale)
                    assertTrue(
                        "A \${width}x\$height window at scale \$scale asked for \$hero.",
                        hero >= 0.dp,
                    )
                    assertTrue(
                        "A \${width}x\$height window at scale \$scale overflowed its room.",
                        hero <= (width.dp - StoryArcSpace.gutter * 2).coerceAtLeast(0.dp),
                    )
                }
            }
        }
    }

    @Test
    fun `a short window gets a smaller card than its width would allow`() {
        val short = homeHeroWidth(windowWidthDp = 360, windowHeightDp = 800, fontScale = 1f)
        val roomy = homeHeroWidth(windowWidthDp = 360, windowHeightDp = tall, fontScale = 1f)

        assertTrue("A 360 x 800 phone should not get the card a tall one gets.", short < roomy)
    }
}
