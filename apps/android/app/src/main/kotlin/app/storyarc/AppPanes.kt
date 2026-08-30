package app.storyarc

import androidx.compose.runtime.Composable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import app.storyarc.core.designsystem.navigation.StoryArcListDetailPanes
import app.storyarc.core.designsystem.theme.StoryArcWindowClass
import app.storyarc.core.designsystem.theme.rememberWindowClass
import app.storyarc.core.model.AppSettings
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
    /** The page beside the shelf, or `null` while only the shelf is showing. */
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
    if (split == null) {
        remembered.SaveableStateProvider(navigation.stateKey) {
            SingleColumn(host, navigation, settings, onSettingsChange, onResetSettings)
        }
        return
    }
    StoryArcListDetailPanes(
        showsDetail = split.detail != null,
        listPane = {
            remembered.SaveableStateProvider(PaneSplit.listPaneKey) {
                Destination(host = host, destination = AppDestination.LIBRARY)
            }
        },
        detailPane = {
            // Nothing at all rather than a placeholder telling the reader to pick something.
            // The scaffold has already given the whole width to the shelf, so there is no
            // empty column here for a sentence to sit in.
            split.detail?.let { page ->
                remembered.SaveableStateProvider(navigation.stateKey) {
                    HostedScreen(
                        host = host,
                        screen = page,
                        settings = settings,
                        onSettingsChange = onSettingsChange,
                        onResetSettings = onResetSettings,
                    )
                }
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
