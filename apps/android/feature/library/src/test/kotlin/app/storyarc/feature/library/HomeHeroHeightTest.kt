package app.storyarc.feature.library

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
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
 * **A small phone is close to the line, and the number is written down here so the next
 * reader does not have to rediscover it.** On the reference emulator the hero uses 492 dp of
 * 658, which is comfortable. On a 360 × 800 dp phone — a small modern device, and the
 * smallest shape worth worrying about — the same hero uses 492 of 544, leaving 52 dp where
 * a section heading wants about 56. So the heading is roughly its own height below the fold
 * there, and was *not* before the byline and the resume row were added. The card cannot give
 * the space back without either clipping its own caption or dropping below
 * [homeHeroWidth]'s phone tier, which `design.md` §4 fixes and `HomeCoverWidthTest` pins. It
 * is recorded rather than fixed by guesswork: the frame owed for task 0b.4 is what says
 * whether a real 360 dp device agrees, and a device is the only thing that can.
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
         * What Home spends above and below the hero.
         *
         * `MediumFlexibleTopAppBar` expanded, which is 112 dp **including** the status bar it
         * pads itself for; `ShortNavigationBar`, 64 dp plus the gesture inset it applies
         * itself, so about 88; and the *Keep reading* heading with its air, 56. The gesture
         * inset is counted once, inside the navigation bar — adding it again is the mistake
         * that makes this model look 48 dp more pessimistic than the device.
         */
        const val CHROME_DP = 112 + 88 + 56

        /** A section heading and the air above it, which is what has to remain visible. */
        const val NEXT_HEADING_DP = 56
    }

    private fun room(heightDp: Int): Dp = (heightDp - CHROME_DP).dp

    private fun hero(widthDp: Int, fontScale: Float = 1f): Dp =
        homeHeroBlockHeight(homeHeroWidth(widthDp, fontScale), fontScale)

    @Test
    fun `the next heading is visible without scrolling at the default text size`() {
        val room = room(REFERENCE_HEIGHT_DP)
        val hero = hero(REFERENCE_WIDTH_DP)

        assertTrue(
            "The hero block is $hero in $room of room, leaving ${room - hero} — the next" +
                " section's heading needs $NEXT_HEADING_DP.dp and would be below the fold.",
            room - hero >= NEXT_HEADING_DP.dp,
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
        val hero = hero(REFERENCE_WIDTH_DP)

        assertTrue(
            "The hero block is $hero in $room of room — that is a shelf cell, not a hero.",
            hero >= room / 3,
        )
    }

    @Test
    fun `a small phone is within one heading of the fold, and this is where that is recorded`() {
        // Not an assertion that it fits — it does not, by about 4 dp, and this class's note
        // says why that is left alone rather than guessed at. What is asserted is the size
        // of the shortfall, so that a change which makes it *much* worse fails here instead
        // of being found on a device three weeks later.
        val room = room(SMALL_HEIGHT_DP)
        val hero = hero(SMALL_WIDTH_DP)
        val left = room - hero

        assertTrue(
            "A 360 × 800 phone now leaves $left for the next heading. It left 52.dp on" +
                " 2026-09-05; losing another heading's worth is a regression, not a rounding.",
            left >= (NEXT_HEADING_DP - 16).dp,
        )
    }

    @Test
    fun `a reader at the largest text size gets a taller card, not a clipped caption`() {
        // No fold claim here, and that is deliberate. `home-screen` scopes the scenario to
        // "the default text size", and a reader at 200% has accepted that less fits on a
        // screen — what they must not get is a caption cut off, which is what a height
        // budget that ignored the scale would give them. So the assertion is that the budget
        // moves at all.
        assertTrue(
            "The height budget ignores the reader's text size.",
            hero(REFERENCE_WIDTH_DP, fontScale = 2f) > hero(REFERENCE_WIDTH_DP),
        )
    }
}
