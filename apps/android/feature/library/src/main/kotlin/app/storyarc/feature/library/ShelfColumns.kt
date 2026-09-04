package app.storyarc.feature.library

import androidx.compose.ui.unit.Dp
import app.storyarc.core.designsystem.grid.BoundedAdaptive
import app.storyarc.core.designsystem.grid.coverMaximumWidth
import app.storyarc.core.designsystem.grid.coverMinimumWidth

/**
 * The bounds the library's own cover shelf lays its columns out between.
 *
 * **The same rule, asked of the room the shelf actually has.** `rememberCoverColumns` reads
 * the *window*, which is right for a full-width surface and wrong for this one: on a
 * 1280 × 576 dp tablet the library draws inside the ~360 dp list pane of a
 * `ListDetailPaneScaffold`, reads 1280 dp, takes the 158 dp tier — and a pane with 320 dp of
 * content room then fits exactly one 168 dp cover with 170 dp of empty pane beside it.
 * Measured on its own width the same pane takes the 104 dp tier and fits three.
 *
 * `design.md` §4 records this as an open divergence rather than a decision: iOS passes the
 * shelf's width (`coverMinimumWidth(shelfWidth:textSize:)`) and Android passed the window's,
 * "not a licence to copy the shape — a thing to settle". This settles it for the one shelf
 * that is ever laid out inside a pane, and settles it iOS's way, because the frame shows what
 * the other answer costs. **`CoverColumns.kt` is untouched**: the ladder, the cap and the
 * accessibility step are still asked of the design system and still stated in exactly one
 * place. What changed is the width this shelf hands them.
 *
 * The breakpoints keep the meaning the design system gives them here — 600 and 840 sort a
 * *shelf* into narrow, medium and wide, which is the question a cover width is really asking.
 * The window-size-class reading of them, which `rememberCoverColumns` keeps, belongs to the
 * pane count, and nothing here touches that.
 *
 * Pure and not `@Composable`, so the pane case can be asserted without one.
 */
internal object ShelfColumns {

    /**
     * @param shelfWidth how wide the shelf itself is — the pane, not the window.
     * @param fontScale the reader's text size. The second input to a cover's width, not only
     *   the room: three columns of caption at an accessibility size is a recognisable cover
     *   under an unreadable label.
     */
    fun of(shelfWidth: Dp, fontScale: Float): BoundedAdaptive = BoundedAdaptive(
        minSize = coverMinimumWidth(shelfWidth.value.toInt(), fontScale),
        maxSize = coverMaximumWidth(fontScale),
    )
}
