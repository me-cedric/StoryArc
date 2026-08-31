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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
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

    // Material's own suggestion, from the V2 measurement rather than the deprecated one that
    // knows only three width classes — but used for the *bar*, not for the choice between a
    // bar and a rail. That choice is `showsSidebar`'s, because the screens drawn inside this
    // shell ask `showsSidebar` too, and the two answers have to be the same answer: Material
    // reads the height as well as the width, so a phone in landscape at 800 x 360 dp got a
    // bar here while the library dropped Shelves and Settings from its toolbar on the
    // strength of a rail that was not there.
    val suggested = NavigationSuiteScaffoldDefaults.navigationSuiteType(currentWindowAdaptiveInfoV2())
    val isRail = windowClass.showsSidebar

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
        isRail && isOpen -> NavigationSuiteType.WideNavigationRailExpanded
        isRail -> NavigationSuiteType.WideNavigationRailCollapsed
        // A bar, and Material's own choice of which one — it has two, and the wider of them
        // is the right one on a window that is wide but not wide enough for a rail.
        suggested == NavigationSuiteType.ShortNavigationBarMedium -> suggested
        else -> NavigationSuiteType.ShortNavigationBarCompact
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
                            label = { EntryLabel(entry, type.pinsLabelFontScale) },
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
                            label = { EntryLabel(entry, type.pinsLabelFontScale) },
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

/**
 * The font scale a navigation label is drawn at, whatever the reader's own is.
 *
 * **Material's own navigation bar does not scale its labels with the system font size**, and
 * this is that rule ported. `NavigationBarItemView.setTextAppearanceWithoutFontScaling` is
 * where Material does it, `labelFontScalingEnabled` is the attribute that turns it back on,
 * and it defaults to off -- which is why every stock Material app on the device draws small
 * navigation labels at a large font scale. The Compose `ShortNavigationBarItem` has no
 * equivalent, because the label is the caller's composable, so the caller has to carry it.
 *
 * The reason is arithmetic rather than taste. A bar splits its width equally between its
 * destinations, so on a 360 dp phone each of StoryArc's three gets 120 dp and no more. At the
 * largest accessibility text size "Downloads" grew to fill that 120 dp edge to edge and sat
 * against the display's own boundary; French's "Téléchargements" is six characters longer
 * again. Material forbids both ways out of that -- "avoid long text labels as these labels do
 * not truncate or wrap" and "avoid shrinking text labels to fit on a single line" -- and
 * `native-experience` forbids the third, dropping the label, because a destination may never
 * be an unlabelled icon. What is left is the label not growing in the first place.
 *
 * So this is a deliberate exception to `design.md`'s "all scale with the Android font scale",
 * scoped to the eight or so words in the navigation control, and only where the arithmetic
 * above applies -- see [NavigationSuiteType.pinsLabelFontScale]. A screen reader is
 * unaffected everywhere: the label is the item's name and TalkBack reads it whatever size it
 * is drawn at.
 */
private const val NavigationLabelFontScale = 1f

/**
 * Whether this control is one whose labels have to be held to their design size.
 *
 * The bar and the collapsed rail are: both split a fixed, narrow measure between a fixed
 * number of destinations, and neither can give a label more room than that share. The
 * **expanded rail is not** -- it is as wide as its own open state and it is the only control
 * that draws the secondary entries at all, so there is nothing there for the pin to prevent
 * and taking a reader's text size away would be a cost with no purchase.
 *
 * A branch rather than one blanket rule, because the reason for the rule genuinely stops at
 * this boundary. `NavigationSuiteType.None` draws no label to pin.
 */
internal val NavigationSuiteType.pinsLabelFontScale: Boolean
    get() = this != NavigationSuiteType.WideNavigationRailExpanded

/**
 * The density a navigation label measures against.
 *
 * Its own function so the rule above can be asserted without a device, and so the
 * substitution is a value rather than a lambda buried in a composition local.
 */
internal fun navigationLabelDensity(density: Density, isPinned: Boolean): Density =
    if (!isPinned || density.fontScale == NavigationLabelFontScale) {
        density
    } else {
        Density(density.density, NavigationLabelFontScale)
    }

/**
 * A destination's name, one line, in the bar and in the rail alike.
 *
 * The ellipsis is a guard rather than the plan: with [NavigationLabelFontScale] holding the
 * label to its design size, the longest name in any of the four shipped languages fits the
 * narrowest third this app supports. If a fifth language ever does not, a reader gets a
 * shortened word rather than one cut off at the glass.
 */
@Composable
private fun EntryLabel(entry: NavigationEntry, isPinned: Boolean) {
    val density = navigationLabelDensity(LocalDensity.current, isPinned)
    CompositionLocalProvider(LocalDensity provides density) {
        Text(text = entry.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
