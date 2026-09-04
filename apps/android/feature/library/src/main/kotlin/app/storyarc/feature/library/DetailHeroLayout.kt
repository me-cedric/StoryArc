package app.storyarc.feature.library

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/** The tallest the cover is drawn. Beyond this a tablet shows a poster nobody asked for. */
private val COVER_MAXIMUM = 360.dp

/**
 * The shortest the cover is drawn before the hero stops trying.
 *
 * A window with less room than this has a scroll either way, and a cover below it is a
 * favicon — `publication-detail` asks for artwork the reader can look at.
 */
private val COVER_MINIMUM = 72.dp

/**
 * How much of the window's height the artwork may take when the page stacks.
 *
 * Bounded by height rather than by width, which is what a 2:3 object on a tall phone
 * actually needs: 260 dp of width is 390 dp of height, and that plus an app bar is the
 * whole viewport.
 */
private const val COVER_SHARE_OF_WINDOW = 0.4f

/** What the page spends above and below the hero: [PublicationDetailScreen]'s own padding. */
private val PAGE_PADDING = StoryArcSpace.lg

/** What the hero spends inside its own container, per edge, when it stacks. */
private val HERO_PADDING = StoryArcSpace.xl

/**
 * And per edge when it lays out side by side.
 *
 * Less, because on a short window every dp of padding comes straight off the artwork: at
 * 800 x 360 the difference between this and [HERO_PADDING] is a sixth of the cover.
 */
private val HERO_PADDING_BESIDE = StoryArcSpace.lg

/** The gap between the cover and the action when they are stacked. */
private val HERO_GAP = StoryArcSpace.xl

/** A filled Material button. Material's own height, not a guess — `Button` is 40 dp tall. */
private val ACTION_HEIGHT = 40.dp

/**
 * How the publication page's hero arranges itself in the room it actually has.
 *
 * **The defect this exists for: at 800 × 360 dp there was no way to open a book from its own
 * page.** A `LargeFlexibleTopAppBar` with a subtitle is 152 dp whatever the window, the
 * navigation bar takes 88 more, and the cover was budgeted against the *window* rather than
 * against what was left — so on a landscape phone the hero was 256 dp tall inside a 96 dp
 * viewport and `publication-detail`'s "one primary action" sat 112 dp below the fold, on the
 * screen whose entire point is that action. No amount of shrinking the cover fixes it: for
 * the button to clear a collapsed viewport the artwork would have to be 24 dp tall.
 *
 * So a short window turns the hero on its side. 800 dp of width was being spent on wash
 * around a 96 dp cover; putting the action beside the artwork instead of under it takes the
 * hero from 256 dp to about 152 and the action is on screen with nothing to scroll.
 *
 * A window with room to stack is untouched, and that is checked rather than assumed — the
 * arithmetic below asks whether the stacked hero *fits* before it changes anything, so a
 * phone and a tablet draw exactly what they drew.
 *
 * Pure, so every window in the matrix can be asserted without one. `HomeCoverWidthTest` is
 * the same reach for the same reason on the previous destination.
 *
 * @property isSideBySide whether the cover and the action share a row.
 * @property coverHeight how tall the artwork is drawn; its width follows the 2:3 proportion.
 * @property padding what the container spends inside itself, per edge.
 */
internal data class DetailHeroLayout(
    val isSideBySide: Boolean,
    val coverHeight: Dp,
    val padding: Dp = HERO_PADDING,
) {

    companion object {
        /**
         * @param windowHeight the whole window, which is what the stacked cover has always
         *   been budgeted against and still is.
         * @param room the page's own viewport — the window less the status bar, the app bar
         *   and the navigation bar. Measured rather than derived, because the app bar's
         *   height is Material's and the navigation bar is taken before this page is
         *   measured at all.
         */
        fun of(windowHeight: Dp, room: Dp): DetailHeroLayout {
            val stackedCover = minOf(windowHeight * COVER_SHARE_OF_WINDOW, COVER_MAXIMUM)
            val stacked =
                PAGE_PADDING * 2 + HERO_PADDING * 2 + stackedCover + HERO_GAP + ACTION_HEIGHT
            if (stacked <= room) {
                return DetailHeroLayout(false, stackedCover, HERO_PADDING)
            }
            val beside = room - PAGE_PADDING * 2 - HERO_PADDING_BESIDE * 2
            return DetailHeroLayout(
                isSideBySide = true,
                coverHeight = beside.coerceIn(COVER_MINIMUM, stackedCover),
                padding = HERO_PADDING_BESIDE,
            )
        }
    }
}
