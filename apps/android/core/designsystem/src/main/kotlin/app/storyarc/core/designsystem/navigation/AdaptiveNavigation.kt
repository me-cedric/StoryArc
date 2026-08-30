package app.storyarc.core.designsystem.navigation

import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette

/**
 * **The one place an experimental Material 3 Expressive API may be opted into.**
 *
 * `MaterialShapes` and `LoadingIndicator` are still `@ExperimentalMaterial3ExpressiveApi`.
 * Opted into at twenty call sites, the next alpha bump is a twenty-file repair; opted into
 * here and re-exported as a plain composable, it is one. Nothing in this file needs an
 * opt-in *today* — the navigation shell below is stable API on material3 1.5.0-alpha26 —
 * and that is the point: the address exists before the first caller needs it.
 *
 * A wrapper earns its place here when the Expressive API it hides is experimental. A stable
 * Material component is used directly at its call site, not re-exported through here.
 */

/**
 * One destination in the app's persistent navigation.
 *
 * A plain value rather than a composable slot, so the destination set can be built,
 * ordered and asserted without a device — which is the whole reason the app layer holds a
 * typed navigation model rather than a stack of booleans.
 */
data class NavigationEntry(
    /**
     * Always present. `native-experience` never lets state be carried by an icon alone, and
     * Material caps a navigation bar at three to five destinations precisely so every one of
     * them can be labelled.
     */
    val label: String,
    val icon: ImageVector,
    val selected: Boolean,
    val onSelect: () -> Unit,
)

/**
 * The frame every browse surface draws inside.
 *
 * Material's own [NavigationSuiteScaffold], not a hand-built bar: it chooses a short
 * navigation bar on a phone, and a wide navigation rail once the window has room for one,
 * from the window itself rather than from a device check. A fold, an unfold, a rotation and
 * a multi-window drag are all the same event to it — the window measured differently.
 *
 * `navigation-shell` asks that the same three destinations stay present, in the same order,
 * in whatever wide-window navigation the platform provides. That is exactly what this
 * scaffold does with one list, which is why the destination set is passed as data and the
 * shape of the control is not decided here at all.
 *
 * The colour rule of the design direction is applied in the one place it can be: the
 * navigation component keeps Material's own — and therefore dynamic — container, because
 * chrome is where Material You earns its keep; the ground behind the content is StoryArc's
 * `surfaceCanvas`, because a wallpaper-derived wash across a wall of covers destroys the one
 * thing a reader uses to tell one book from another.
 *
 * @param showsNavigation `false` where the screen owns the whole window — the reader, and
 *   the screens a reader comes back from rather than stays in. The scaffold keeps its
 *   content and drops the control, so nothing is re-laid-out when it returns.
 */
@Composable
fun AdaptiveNavigationShell(
    entries: List<NavigationEntry>,
    modifier: Modifier = Modifier,
    showsNavigation: Boolean = true,
    /**
     * Entries a rail has room for and a navigation bar has not.
     *
     * Drawn only where the window is wide enough for a rail, and never in the bar: Material
     * caps a navigation bar at three to five destinations, and `navigation-shell` fixes the
     * destination set at three. These are the secondary entries the same requirement allows
     * a wide window to reveal — sections and shelves, never a configured source.
     */
    secondaryEntries: List<NavigationEntry> = emptyList(),
    content: @Composable () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    // The V2 measurement, not the one the scaffold defaults to: the original reports three
    // width classes, and the deprecated call says so itself. This one carries Material's
    // large and extra-large classes as well, which is the measurement the tablet slice needs
    // and the one this shell should already be reading.
    val type = NavigationSuiteScaffoldDefaults.navigationSuiteType(currentWindowAdaptiveInfoV2())
    val isRail = type == NavigationSuiteType.WideNavigationRailCollapsed ||
        type == NavigationSuiteType.WideNavigationRailExpanded
    NavigationSuiteScaffold(
        modifier = modifier,
        navigationSuiteItems = {
            (if (isRail) entries + secondaryEntries else entries).forEach { entry ->
                item(
                    selected = entry.selected,
                    onClick = entry.onSelect,
                    icon = { Icon(entry.icon, contentDescription = null) },
                    label = {
                        Text(text = entry.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    },
                    alwaysShowLabel = true,
                )
            }
        },
        layoutType = if (showsNavigation) type else NavigationSuiteType.None,
        containerColor = palette.surfaceCanvas,
        content = content,
    )
}
