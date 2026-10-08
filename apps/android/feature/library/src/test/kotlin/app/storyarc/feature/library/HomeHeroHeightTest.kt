package app.storyarc.feature.library

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That the hero leaves the next section's heading on screen.
 *
 * `home-screen`, *The hero does not crowd out the rest of the surface*: on a phone at the
 * default text size "the next section's heading is visible without scrolling, so a reader
 * can see that the surface continues", while the card "stays large enough to be the
 * surface's one emphasis". Both halves, because either one alone has a trivial wrong answer
 * — a thumbnail passes the first and a full-bleed poster passes the second.
 *
 * **This is arithmetic, and arithmetic is not the proof.** What it checks is the height the
 * carousel states before it lays anything out. It cannot see a title that wrapped to three
 * lines, a display cutout, or a system bar taller than the model below. A screenshot from a
 * booted emulator is what proves the sum was measuring the right thing, and AGENTS.md §6
 * requires one. What this catches is the regression *between* screenshots: another line in
 * the caption, another control on the card, a tier widened. Every one of those has happened
 * to this card already — the byline and the resume row both landed on 2026-09-05, and each
 * one grew this number.
 *
 * **A compact height gives up cover width to keep the heading.** The frames of task 0b.4 showed
 * the heading cut by the navigation bar on the reference phone and on a 360 x 800 dp phone,
 * because the height model was 74 dp optimistic. Owner answer O17 chose to shrink the cover tier
 * on a compact height rather than accept the heading below the fold, so the model now carries
 * the measured chrome and [homeHeroArtHeight] shortens the cover box where the window is short,
 * keeping the card's width (a Resume button wraps in a narrower card).
 */
class HomeHeroHeightTest {

    private companion object {
        /**
         * The emulator every Android frame in `docs/designs/screenshots/` is taken on:
         * `storyarc-j6`, 1080 × 2400 at 420 dpi, so 411 × 914 dp.
         */
        const val REFERENCE_WIDTH_DP = 411
        const val REFERENCE_HEIGHT_DP = 914

        /** A small modern phone, for the number in this class's own note. */
        const val SMALL_WIDTH_DP = 360
        const val SMALL_HEIGHT_DP = 800

        /**
         * What Home spends above and below the hero, **as measured on a frame**.
         *
         * Task 0b.4, 2026-10-08, Pixel 6a emulator, 411 x 914 dp, gesture navigation: the card
         * starts 242 dp from the top and the navigation bar starts at 826 dp, so the top bar,
         * the section heading and their air take 242 and the navigation bar takes 88.
         * The earlier model said 112 + 88 + 56 = 256 and was 74 dp optimistic, which is why the
         * reference phone failed on its frame too. The number is 318 rounded up, plus the few dp by which the
         * height model overstates the card.
         */
        const val CHROME_DP = 324

        /**
         * From the card's bottom edge to the bottom of the next heading's text, which is what has to
         * remain visible. Measured on the same frame: about 66 dp.
         */
        const val NEXT_HEADING_DP = 68

        /** The width is the inverse of the height, so the fit is exact up to float rounding. */
        const val ROUNDING_DP = 0.5f
    }

    private fun room(heightDp: Int): Dp = (heightDp - CHROME_DP).dp

    private fun hero(widthDp: Int, heightDp: Int, fontScale: Float = 1f): Dp =
        homeHeroBlockHeight(homeHeroWidth(widthDp, heightDp, fontScale), heightDp, fontScale)

    @Test
    fun `the next heading is visible without scrolling at the default text size`() {
        val room = room(REFERENCE_HEIGHT_DP)
        val hero = hero(REFERENCE_WIDTH_DP, REFERENCE_HEIGHT_DP)

        assertTrue(
            "The hero block is $hero in $room of room, leaving ${room - hero} — the next" +
                " section's heading needs $NEXT_HEADING_DP.dp and would be below the fold.",
            room - hero >= (NEXT_HEADING_DP - ROUNDING_DP).dp,
        )
    }

    @Test
    fun `the card is still the surface's one emphasis`() {
        // The other half of the same scenario, and the reason the test above cannot simply
        // be satisfied by shrinking the card: the hero is "a resume affordance and not a
        // thumbnail". A third of the room it is given is the floor — the plain shelves below
        // it draw covers about a third of this size, and a hero that had shrunk to theirs
        // would be a fourth shelf rather than the surface's one emphasis.
        val room = room(REFERENCE_HEIGHT_DP)
        val hero = hero(REFERENCE_WIDTH_DP, REFERENCE_HEIGHT_DP)

        assertTrue(
            "The hero block is $hero in $room of room — that is a shelf cell, not a hero.",
            hero >= room / 3,
        )
    }

    @Test
    fun `the next heading is visible on a small phone too`() {
        // Owner answer O17: the card gives up cover width on a compact height rather than
        // letting the heading fall below the fold. A 200 dp floor on the card's width stopped
        // the card from shrinking far enough at 360 x 800 dp, and a narrower card wraps the
        // Resume button, so the cover box gives up height instead.
        val room = room(SMALL_HEIGHT_DP)
        val hero = hero(SMALL_WIDTH_DP, SMALL_HEIGHT_DP)

        assertTrue(
            "A 360 x 800 phone leaves ${room - hero} for the next heading, which needs $NEXT_HEADING_DP.dp.",
            room - hero >= (NEXT_HEADING_DP - ROUNDING_DP).dp,
        )
    }

    @Test
    fun `the small phone's card is still the surface's one emphasis`() {
        val room = room(SMALL_HEIGHT_DP)
        val hero = hero(SMALL_WIDTH_DP, SMALL_HEIGHT_DP)

        assertTrue("The hero block is $hero in $room of room.", hero >= room / 3)
    }

    @Test
    fun `the small phone keeps a card wide enough for its buttons`() {
        // A 200 dp card is the narrowest that keeps "Resume" on one line (the frame of task
        // 0b.4 at 138 dp showed it wrapped to "Resu / me"), so the height is given up by the
        // cover box and not by the width.
        assertTrue(
            homeHeroWidth(SMALL_WIDTH_DP, SMALL_HEIGHT_DP, fontScale = 1f) >= 200.dp,
        )
    }

    @Test
    fun `a reader at the largest text size gets room for the caption, not a clipped one`() {
        // No fold claim here, and that is deliberate. `home-screen` scopes the scenario to
        // "the default text size", and a reader at 200% has accepted that less fits on a
        // screen. What they must not get is a caption cut off, which is what a height budget
        // that ignored the scale would give them. In a window with room to spare the block must
        // grow with the text.
        val tall = 2000
        val width = homeHeroWidth(REFERENCE_WIDTH_DP, tall, fontScale = 1f)

        assertTrue(
            "The height budget ignores the reader's text size.",
            homeHeroBlockHeight(width, tall, fontScale = 2f) > homeHeroBlockHeight(width, tall, fontScale = 1f),
        )
    }

    @Test
    fun `the cover box is never taller than 2 to 3, and never negative`() {
        for (height in listOf(0, 200, 411, 640, 800, 914, 2000)) {
            val box = homeHeroArtHeight(homeHeroWidth(360, height, 1f), height, 1f)
            assertTrue("A ${height}dp window gave a cover box of $box.", box > 0.dp)
            assertTrue(box <= (homeHeroWidth(360, height, 1f) - StoryArcSpace.md * 2) * HOME_COVER_ASPECT)
        }
    }
}
