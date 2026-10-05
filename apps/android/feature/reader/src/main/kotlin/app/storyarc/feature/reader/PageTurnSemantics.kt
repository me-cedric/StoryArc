package app.storyarc.feature.reader

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription

/**
 * A named page turn, and the position the reader lands on.
 *
 * `native-experience`, *Screen reader*: "the reader announces the page number and total on
 * each turn, and offers gestures to turn pages". Neither held here. The pager contributed
 * the system's own scroll actions, which name a direction on screen rather than a page, and
 * Fast fade is not a pager at all, so that mode offered nothing. Nothing was announced after
 * a turn by any means.
 *
 * **The announcement is a live region on the position, not a call at each turn site.** The
 * page moves from a tap zone, an arrow key, a game controller, a volume button, a swipe and
 * now these two actions, and a reader who misses one of those paths gets silence that looks
 * exactly like the rest working. A live region reads the page the reader is on, so every path
 * announces by construction.
 *
 * The sentence is `reader_page_label`, which is already what each page answers to a screen
 * reader. One position, phrased one way (`comic-reader`).
 *
 * [page] is in the publication's own numbering, counted from one, like the label.
 */
@Composable
internal fun Modifier.pageTurnSemantics(
    page: Int,
    count: Int,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
): Modifier {
    val position = stringResource(R.string.reader_page_label, page, count)
    val next = stringResource(R.string.reader_turn_next_page)
    val previous = stringResource(R.string.reader_turn_previous_page)
    return semantics {
        liveRegion = LiveRegionMode.Polite
        stateDescription = position
        customActions = listOf(
            CustomAccessibilityAction(next) { onNext(); true },
            CustomAccessibilityAction(previous) { onPrevious(); true },
        )
    }
}
