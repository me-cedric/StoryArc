package app.storyarc

import androidx.compose.runtime.Composable
import androidx.compose.runtime.movableContentOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import app.storyarc.core.designsystem.navigation.StoryArcListDetailPanes
import app.storyarc.core.designsystem.theme.StoryArcWindowClass
import app.storyarc.core.designsystem.theme.rememberWindowClass
import app.storyarc.core.model.AppSettings
import app.storyarc.feature.library.PublicationPanePlaceholder
import app.storyarc.navigation.AppDestination
import app.storyarc.navigation.AppNavigation
import app.storyarc.navigation.Screen

/**
 * What the window is showing, once the window's width has had its say.
 *
 * A pure function of the two things that decide it, so the whole rule can be asserted
 * without a device — the same reason [AppNavigation] is a value rather than a pile of
 * booleans. There is no state here: the path is still the only truth, and this reads it.
 */
internal data class PaneSplit(
    /**
     * The page beside the shelf, or `null` while the second pane is still showing its one
     * sentence. Either way there are two panes — see `PublicationPanePlaceholder`.
     */
    val detail: Screen.PublicationPage?,
) {
    companion object {
        /**
         * Two panes, or `null` for the one-column layout every other case gets.
         *
         * Three conditions, all of them necessary.
         *
         * **The window has room.** 840 dp, Material's expanded boundary — not the 600 dp
         * where the rail arrives. Below it a detail is a place the reader goes to; at and
         * above it a detail is a place the reader looks at, with the shelf still beside it.
         *
         * **The reader is in the library.** Home and Downloads are single surfaces; a shelf
         * and the page of a book on it are the one pair in this app that is a list and its
         * detail.
         *
         * **The path is the shelf, or the shelf with one page open on it.** Anything deeper
         * — a server browser, a collection, Settings — is a screen in its own right and takes
         * the window, exactly as it does on a phone. Stated as a shape rather than as a flag,
         * so a fifteenth screen cannot arrive and quietly find itself in half a window.
         */
        fun of(navigation: AppNavigation, windowClass: StoryArcWindowClass): PaneSplit? {
            if (!windowClass.showsTwoPanes) return null
            if (navigation.destination != AppDestination.LIBRARY) return null
            val stack = navigation.stack
            return when {
                stack.isEmpty() -> PaneSplit(detail = null)
                stack.size == 1 -> (stack.single() as? Screen.PublicationPage)?.let(::PaneSplit)
                else -> null
            }
        }

        /**
         * The saved state of the shelf itself, named the same whether it is a whole window
         * or the left half of one.
         *
         * Asked of a navigation rather than written out, so the key cannot drift from the one
         * [AppNavigation.stateKey] produces — which is the point: a reader who opens a page
         * on a tablet must not lose the scroll position of the shelf behind it, and they
         * would if the two layouts named the same position differently.
         */
        val listPaneKey: String = AppNavigation(AppDestination.LIBRARY).stateKey
    }
}

/**
 * Draws [content] so that a structural branch elsewhere in the tree — an `if` that takes a
 * different path — reparents it instead of tearing it down and building it again.
 *
 * [AppContent] used to reach the shelf through two different call sites: one for the single
 * column, one for [StoryArcListDetailPanes]'s list pane. Compose does not know those two
 * calls are "the same shelf, wider now" — a structural branch disposes its whole subtree the
 * moment the branch taken changes, however equal the leaf composable's own arguments are. A
 * rotation that crosses 840 dp took exactly that branch, on every rotation, which is
 * `finishDrawing of orientation change` at 3305 ms on the field report task 21.1 fixes: the
 * whole shelf — every cover, every grid cell — decoded and laid out again from nothing,
 * every time the window crossed the threshold.
 *
 * [movableContentOf] is the platform's own answer to that: remembered once, the returned
 * function moves its content between call sites rather than recreating it, so a rotation
 * becomes a relayout instead of a rebuild. It must be called from at most one place in the
 * composition at a time — the two call sites here are an `if`/`else` (through
 * [StoryArcListDetailPanes]), never both branches of one.
 */
@Composable
internal fun rememberMovablePane(content: @Composable () -> Unit): @Composable () -> Unit =
    remember { movableContentOf(content) }

/**
 * The same move, for content that takes one argument whose identity changes between calls —
 * which page, here — while the call site itself still only moves rather than rebuilds.
 *
 * [movableContentOf]'s own parameterised overload takes the argument as a plain function
 * parameter, so each call passes its own current page straight through; nothing is captured
 * and frozen at the first composition the way a value closed over from the surrounding
 * function would be. [remember]'s block still runs once, which is what keeps this the one
 * continuation [AppContent]'s two call sites share.
 */
@Composable
internal fun <T> rememberMovablePane(content: @Composable (T) -> Unit): @Composable (T) -> Unit =
    remember { movableContentOf(content) }

/**
 * Everything under the navigation control.
 *
 * One column, or two where the window and the path both allow it. The split is derived, not
 * held: pressing back pops the page off the path, and the pane closes because there is
 * nothing in it any more. That is why there is no second back stack here and no
 * `NavigableListDetailPaneScaffold` — one back rule, in
 * [AppNavigation.back], as it has been since the navigation rewrite.
 */
@Composable
internal fun AppContent(
    host: AppHost,
    navigation: AppNavigation,
    settings: AppSettings,
    onSettingsChange: (AppSettings) -> Unit,
    onResetSettings: () -> Unit,
) {
    // What each position on each destination's path remembered — a scroll offset, an open
    // filter, a text field. Keyed on the position rather than on the screen, so leaving a
    // destination and coming back is "a return rather than a reset", and popping a screen
    // forgets what only that screen knew.
    val remembered = rememberSaveableStateHolder()
    val split = PaneSplit.of(navigation, rememberWindowClass())

    // The shelf, named once. Both the single-column branch below and the list pane inside
    // `StoryArcListDetailPanes` call this same value — never a fresh `Destination(...)` of
    // their own — so rotating past 840 dp moves it instead of rebuilding it.
    val shelf = rememberMovablePane {
        remembered.SaveableStateProvider(PaneSplit.listPaneKey) {
            Destination(host = host, destination = AppDestination.LIBRARY)
        }
    }

    // A publication page has the same problem the shelf had, for the same reason: the
    // single column calls `HostedScreen` for it directly, `StoryArcListDetailPanes`' detail
    // pane calls it from inside its own wrapper, and a rotation that crosses 840 dp moves
    // the page between those two shapes. Without this, the *second* `SaveableStateProvider`
    // call restores whatever the *first* last saved — not the position the reader was at
    // the moment of rotation, which that call had not yet saved when the new one composed —
    // so a scrolled page measurably went back to the top on the device (`Read` moved from
    // y=1398 to y=1626 after portrait, landscape, portrait). One continuation, moved rather
    // than rebuilt either way, has nothing to restore from: it is the same state, in place.
    //
    // Parameterised rather than closed over: `navigation`, `settings` and the two callbacks
    // change on every recomposition, and `remember`'s block — the one place `movableContentOf`
    // is called — runs only once. A value closed over there would freeze at whatever it was
    // on the first composition; `rememberUpdatedState` is what keeps each one current without
    // re-running that call.
    val currentNavigation = rememberUpdatedState(navigation)
    val currentSettings = rememberUpdatedState(settings)
    val currentOnSettingsChange = rememberUpdatedState(onSettingsChange)
    val currentOnResetSettings = rememberUpdatedState(onResetSettings)
    val detailPage = rememberMovablePane<Pair<Screen.PublicationPage, Boolean>> { (page, isBesideList) ->
        remembered.SaveableStateProvider(currentNavigation.value.stateKey) {
            HostedScreen(
                host = host,
                screen = page,
                settings = currentSettings.value,
                onSettingsChange = currentOnSettingsChange.value,
                onResetSettings = currentOnResetSettings.value,
                // The shelf is in the other half of this window and never leaves it, so the
                // page draws no back arrow there — see `HostedScreen`'s own parameter for
                // why the rule is carried here rather than inherited from a scaffold. In
                // the single column it is whatever the single column's own rule says.
                isBesideList = isBesideList,
            )
        }
    }

    if (split == null) {
        val screen = navigation.current
        if (navigation.destination == AppDestination.LIBRARY && screen == null) {
            // The single column, sitting on the shelf itself — the one destination that can
            // also be the list pane of a split. Route it through `shelf` rather than through
            // `SingleColumn`'s own generic path, so this is the same call as the one below.
            shelf()
        } else if (navigation.destination == AppDestination.LIBRARY && screen is Screen.PublicationPage) {
            // The one screen that can also be the detail pane of a split. Everything else
            // on this destination's stack, and a publication page opened from a destination
            // that never splits, keeps the plain `SingleColumn` path below: there is only
            // one shape to render it in, so there is nothing for a rotation to move it
            // between.
            detailPage(screen to false)
        } else {
            remembered.SaveableStateProvider(navigation.stateKey) {
                SingleColumn(host, navigation, settings, onSettingsChange, onResetSettings)
            }
        }
        return
    }
    StoryArcListDetailPanes(
        // Always, once the window is wide enough for two. `publication-detail` gives the
        // empty pane a sentence rather than an empty rectangle, so there is something in it
        // before a cover is chosen — and the shelf then keeps one width for the whole
        // visit, instead of reflowing its columns on the first tap and again on the last
        // press of Back.
        showsDetail = true,
        listPane = { shelf() },
        detailPane = {
            val page = split.detail
            if (page == null) {
                PublicationPanePlaceholder()
            } else {
                detailPage(page to true)
            }
        },
    )
}

/** The screen on top of the current destination's path, or the destination's own root. */
@Composable
private fun SingleColumn(
    host: AppHost,
    navigation: AppNavigation,
    settings: AppSettings,
    onSettingsChange: (AppSettings) -> Unit,
    onResetSettings: () -> Unit,
) {
    val screen = navigation.current
    if (screen == null) {
        Destination(host = host, destination = navigation.destination)
    } else {
        HostedScreen(
            host = host,
            screen = screen,
            settings = settings,
            onSettingsChange = onSettingsChange,
            onResetSettings = onResetSettings,
        )
    }
}
