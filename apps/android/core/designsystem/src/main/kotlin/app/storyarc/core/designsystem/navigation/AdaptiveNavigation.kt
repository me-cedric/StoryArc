package app.storyarc.core.designsystem.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.automirrored.filled.MenuOpen
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ShortNavigationBar
import androidx.compose.material3.ShortNavigationBarItem
import androidx.compose.material3.Text
import androidx.compose.material3.WideNavigationRail
import androidx.compose.material3.WideNavigationRailValue
import androidx.compose.material3.WideNavigationRailItem
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldLayout
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.material3.rememberWideNavigationRailState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextOverflow
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.rememberWindowClass
import kotlinx.coroutines.launch

/**
 * **The one place an experimental Material 3 Expressive API may be opted into.**
 *
 * `MaterialShapes` and `LoadingIndicator` are still `@ExperimentalMaterial3ExpressiveApi`.
 * Opted into at twenty call sites, the next alpha bump is a twenty-file repair; opted into
 * here and re-exported as a plain composable, it is one. Nothing in this file needs an
 * opt-in *today* — every component below is stable API on material3 1.5.0-alpha26 — and
 * that is the point: the address exists before the first caller needs it.
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
 * What the rail's menu button is called, in each of its two states.
 *
 * Passed in rather than read from a resource, because `:core:designsystem` deliberately
 * ships no resources: a design system that owned strings would own vocabulary, and the
 * vocabulary belongs to the app. The same reason [NavigationEntry.label] is a `String`.
 */
data class RailMenuLabels(val expand: String, val collapse: String)

/**
 * The frame every browse surface draws inside.
 *
 * Material's own controls and Material's own placement of them: a [ShortNavigationBar]
 * across the foot of a phone, a [WideNavigationRail] down the side of anything wider, and
 * [NavigationSuiteScaffoldLayout] deciding which of the two from the window rather than
 * from a device check. A fold, an unfold, a rotation and a multi-window drag are all the
 * same event to it — the window measured differently.
 *
 * `navigation-shell` asks that the same three destinations stay present, in the same order,
 * in whatever wide-window navigation the platform provides. That is exactly what this does
 * with one list, which is why the destination set is passed as data and the shape of the
 * control is not decided by the caller at all.
 *
 * **The rail has two states and the reader owns which one.** Collapsed it is the three
 * destinations, inside Material's three-to-seven rule for a rail. Opened — behind the menu
 * button in its header — it adds their names and the sections below them. That is Material's
 * own mechanism for the overflow problem the design direction describes, and it is what
 * makes connecting a ninth server safe: the sections were never in the destination set, so
 * they can never push a destination out of it.
 *
 * The colour rule of the design direction is applied in the two places it can be: the
 * navigation control keeps Material's own — and therefore dynamic — container, because
 * chrome is where Material You earns its keep; the ground behind the content is StoryArc's
 * `surfaceCanvas`, because a wallpaper-derived wash across a wall of covers destroys the one
 * thing a reader uses to tell one book from another.
 *
 * @param showsNavigation `false` where the screen owns the whole window — the reader, and
 *   the screens a reader comes back from rather than stays in. The layout keeps its content
 *   and drops the control, so nothing is re-laid-out when it returns.
 */
@Composable
fun AdaptiveNavigationShell(
    entries: List<NavigationEntry>,
    menu: RailMenuLabels,
    modifier: Modifier = Modifier,
    showsNavigation: Boolean = true,
    /**
     * Entries the opened rail reveals, and nothing else ever draws.
     *
     * Never in the navigation bar and never in the collapsed rail: Material caps a
     * navigation bar at three to five destinations, and `navigation-shell` fixes the
     * destination set at three.
     */
    secondaryEntries: List<NavigationEntry> = emptyList(),
    content: @Composable () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val windowClass = rememberWindowClass()
    val scope = rememberCoroutineScope()

    // The V2 measurement, not the one the older call reports: that one knows three width
    // classes and says so itself by being deprecated. This one carries Material's large and
    // extra-large classes as well, which is the measurement a tablet needs.
    val suggested = NavigationSuiteScaffoldDefaults.navigationSuiteType(currentWindowAdaptiveInfoV2())
    val isRail = suggested == NavigationSuiteType.WideNavigationRailCollapsed ||
        suggested == NavigationSuiteType.WideNavigationRailExpanded

    // A window that is large to begin with opens the rail itself, because at that width the
    // labels cost the content nothing. The initial value rather than an effect: the rail
    // animates between the two, and asking it to animate before it has been laid out leaves
    // its width behind what its items think they have.
    val railState = rememberWideNavigationRailState(
        if (windowClass.expandsRailByDefault) {
            WideNavigationRailValue.Expanded
        } else {
            WideNavigationRailValue.Collapsed
        },
    )
    val isOpen = railState.targetValue == WideNavigationRailValue.Expanded

    val type = when {
        !showsNavigation -> NavigationSuiteType.None
        !isRail -> suggested
        isOpen -> NavigationSuiteType.WideNavigationRailExpanded
        else -> NavigationSuiteType.WideNavigationRailCollapsed
    }

    NavigationSuiteScaffoldLayout(
        navigationSuite = {
            when {
                type == NavigationSuiteType.None -> Unit
                isRail -> WideNavigationRail(
                    state = railState,
                    header = {
                        RailMenuButton(
                            isOpen = isOpen,
                            labels = menu,
                            onToggle = { scope.launch { railState.toggle() } },
                        )
                    },
                ) {
                    // The three, always. Then the sections, only while the rail is open —
                    // which is the state the reader asked for by pressing the button above,
                    // so nothing appears or disappears underneath them.
                    (if (isOpen) entries + secondaryEntries else entries).forEach { entry ->
                        WideNavigationRailItem(
                            selected = entry.selected,
                            onClick = entry.onSelect,
                            icon = { Icon(entry.icon, contentDescription = null) },
                            label = { EntryLabel(entry) },
                            railExpanded = isOpen,
                        )
                    }
                }

                else -> ShortNavigationBar {
                    entries.forEach { entry ->
                        ShortNavigationBarItem(
                            selected = entry.selected,
                            onClick = entry.onSelect,
                            icon = { Icon(entry.icon, contentDescription = null) },
                            label = { EntryLabel(entry) },
                        )
                    }
                }
            }
        },
        navigationSuiteType = type,
        content = {
            // The ground the content stands on, painted here because this layout has no
            // container of its own to paint. StoryArc's canvas, not Material's surface: the
            // colour rule scopes dynamic colour to chrome and keeps it off the artwork.
            Box(modifier = modifier.fillMaxSize().background(palette.surfaceCanvas)) {
                content()
            }
        },
    )
}

/**
 * The control that opens and closes the rail.
 *
 * A labelled icon button in the rail's own header slot rather than a fourth item: it is not
 * a place, so it must never carry a selection indicator. `native-experience` still wants a
 * name on it, which here is the content description, because the glyph is the whole control
 * — and the glyph changes with the state, so the button is not leaning on position alone to
 * say which way it goes.
 */
@Composable
private fun RailMenuButton(isOpen: Boolean, labels: RailMenuLabels, onToggle: () -> Unit) {
    IconButton(onClick = onToggle) {
        Icon(
            imageVector = if (isOpen) Icons.AutoMirrored.Filled.MenuOpen else Icons.Filled.Menu,
            contentDescription = if (isOpen) labels.collapse else labels.expand,
        )
    }
}

/** A destination's name, one line, in the bar and in the rail alike. */
@Composable
private fun EntryLabel(entry: NavigationEntry) {
    Text(text = entry.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
}
