@file:OptIn(ExperimentalMaterial3AdaptiveApi::class)

package app.storyarc.core.designsystem.navigation

import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffold
import androidx.compose.material3.adaptive.layout.PaneAdaptedValue
import androidx.compose.material3.adaptive.layout.SupportingPaneScaffold
import androidx.compose.material3.adaptive.layout.ThreePaneScaffoldValue
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirective
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/**
 * **The one place `ExperimentalMaterial3AdaptiveApi` is opted into for a component that
 * draws two panes, and one of two places in the app that opt into it at all.**
 *
 * This comment claimed to be the only one until 2026-09-05, and it was not:
 * `feature/library/…/PublicationDetailScreen.kt` opts into the same API, deliberately.
 * That page asks the pane *directive* whether the window has room for two panes **before**
 * deciding whether to draw a scaffold at all, and draws its one-pane case as a plain
 * `Column` — so neither wrapper below fits it, and hiding a pane instead would leave a
 * shelf the reader cannot reach. Recorded rather than quietly widened: the count is what a
 * reader checks before an alpha bump, and a comment that under-reports it is worse than no
 * comment.
 *
 * The pane scaffolds are stable components on adaptive 1.3.0; the pieces used to *drive*
 * them by hand — `calculatePaneScaffoldDirective`, `PaneAdaptedValue`, `AnimatedPane` — are
 * not. Opted into at every screen that shows two panes, the next release is a repair in as
 * many files; opted into here and re-exported as two plain composables, it is one. Same rule
 * as the Expressive opt-in next door, for the same reason.
 *
 * **Why the scaffolds are driven by a value rather than by their own navigator.** Material
 * ships `NavigableListDetailPaneScaffold`, which wraps the same scaffold around a pane back
 * stack and a predictive-back handler of its own. This app has exactly one back rule — it is
 * a function of `AppNavigation` and lives in one place, and the fourteen-branch state it
 * replaced is the reason that rule exists. A second back stack for the same relationship
 * would be a second copy of the truth, free to disagree with the first about whether a
 * publication is open. So the caller keeps the truth it already holds and hands these the
 * one fact they need — whether the second pane has anything in it — and back stays one rule
 * that hides the pane by popping the screen behind it.
 */

/**
 * A list and the thing chosen from it, side by side.
 *
 * Material's own [ListDetailPaneScaffold]: it decides how the width is divided, animates the
 * pane in and out, and reads the window's hinge so a folded device does not get a pane
 * across the crease. The caller decides only *whether* there is a detail.
 *
 * `publication-detail` makes the seam between the shelf and the page a real place rather
 * than a modal, and at this width it stops being a place a reader travels to at all: the
 * cover is still on screen beside the page it opened.
 *
 * @param showsDetail whether the detail pane has something in it. When it does not, the list
 *   takes the whole window rather than sitting beside an empty column.
 */
@Composable
fun StoryArcListDetailPanes(
    showsDetail: Boolean,
    listPane: @Composable () -> Unit,
    detailPane: @Composable () -> Unit,
    modifier: Modifier = Modifier,
) {
    ListDetailPaneScaffold(
        directive = calculatePaneScaffoldDirective(currentWindowAdaptiveInfoV2()),
        // Primary is the detail and secondary is the list — the scaffold's own naming, and
        // the reason the list is the one that is never hidden here.
        value = ThreePaneScaffoldValue(
            primary = if (showsDetail) PaneAdaptedValue.Expanded else PaneAdaptedValue.Hidden,
            secondary = PaneAdaptedValue.Expanded,
            tertiary = PaneAdaptedValue.Hidden,
        ),
        listPane = { AnimatedPane { listPane() } },
        detailPane = { AnimatedPane { detailPane() } },
        modifier = modifier,
    )
}

/**
 * One thing, with a second view of the same thing beside it.
 *
 * Material's own [SupportingPaneScaffold]. The difference from the pair above is not the
 * layout but the meaning: a supporting pane is *about* what is in the main pane rather than
 * a separate place, which is exactly what a strip of a comic's own pages is. `comic-reader`
 * asks for a thumbnail browser showing every page; on a phone that has to take the screen,
 * and on a tablet it can simply be beside the page without covering it.
 *
 * @param showsSupporting whether the supporting pane is open. The reader's own choice, not
 *   the window's: a window wide enough for the pane is not a reason to force it open over
 *   the artwork.
 */
@Composable
fun StoryArcSupportingPanes(
    showsSupporting: Boolean,
    mainPane: @Composable () -> Unit,
    supportingPane: @Composable () -> Unit,
    modifier: Modifier = Modifier,
) {
    SupportingPaneScaffold(
        directive = calculatePaneScaffoldDirective(currentWindowAdaptiveInfoV2()),
        // Primary is the main pane, secondary the supporting one.
        value = ThreePaneScaffoldValue(
            primary = PaneAdaptedValue.Expanded,
            secondary = if (showsSupporting) PaneAdaptedValue.Expanded else PaneAdaptedValue.Hidden,
            tertiary = PaneAdaptedValue.Hidden,
        ),
        mainPane = { AnimatedPane { mainPane() } },
        supportingPane = { AnimatedPane { supportingPane() } },
        modifier = modifier,
    )
}
