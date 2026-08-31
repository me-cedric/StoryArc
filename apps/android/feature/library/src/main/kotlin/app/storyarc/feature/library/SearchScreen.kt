package app.storyarc.feature.library

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.model.Publication
import app.storyarc.core.model.Source

/**
 * Search, as a place rather than as something done to a shelf.
 *
 * `navigation-shell`: search "SHALL be a place a reader arrives at, and no control SHALL
 * change shape or position to become it". Until this screen existed, Android's search was a
 * field belonging to [LibraryScreen] — so searching was something you did *to* the library,
 * which is the wrong shape for the one question in this app that is not about a shelf:
 * publications arrive from a device, a folder, an OPDS catalogue, a Kavita server and an SMB
 * share, and no shelf shows all of them at once in a way a reader can scan.
 *
 * The screen owns the frame; [LibrarySearchEntry] still owns the question, who is asked and
 * what a row does. That split is the point — the merged local-and-server ranking and the
 * grouping by match kind shipped already and are unchanged by this. What moved is where they
 * are drawn.
 *
 * **The navigation bar needs no hide/show logic here.** The expanded search bar is a
 * full-screen dialog and covers the bar by construction, which is what Material's own
 * navigation-bar page describes: *"temporarily covering the bottom navigation bar until the
 * search flow is completed."* Writing the hide by hand would duplicate the component and
 * fight predictive back.
 *
 * `Scaffold` for the window insets — the navigation shell has taken the bottom one and the
 * status bar is still to pay for — and because `topBar` is where a search bar with a scroll
 * behaviour belongs. The canvas rather than Material's surface, per the colour rule: dynamic
 * colour is scoped to chrome and kept off the artwork.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    viewModel: LibraryViewModel,
    /** How the app layer reaches a publication's own page. */
    onOpenPage: (Publication) -> Unit,
    /** How the app layer reaches a library that is not on this device, carrying the term. */
    onFollowToSource: (Source, String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val query by viewModel.query.collectAsStateWithLifecycle()
    val recents by viewModel.recentSearches.collectAsStateWithLifecycle()

    // Material's own scroll-away-and-return. Made here rather than inside the bar, because the
    // scaffold's content is what has to report the scroll to it: a behaviour made beside the
    // bar would track a scroll nothing tells it about, and the bar would never move.
    val scrollBehavior = SearchBarDefaults.enterAlwaysSearchBarScrollBehavior()

    // `library-browsing` asks the scope to persist "until changed", and a launch is not a
    // change — so the model holds it and `LibraryPreferences` writes it down. This was a
    // `rememberSaveable`, which dies with the process: a reader who narrowed to what is on the
    // device came back to a search that had quietly widened itself.
    //
    // Its own preference key, never the shelf's. `navigation-shell` promises a reader leaving
    // search returns to the destination they were on "with its filters intact", and one shared
    // key would have narrowing a search on a train narrow the shelf they go back to. iOS keeps
    // the two apart the same way, under a second `@AppStorage` key.
    val scope by viewModel.searchScope.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier.fillMaxSize().nestedScroll(scrollBehavior.nestedScrollConnection),
        containerColor = palette.surfaceCanvas,
        topBar = {
            LibrarySearchEntry(
                viewModel = viewModel,
                query = query,
                recents = recents,
                onOpenPage = onOpenPage,
                onFollowToSource = onFollowToSource,
                searchScope = scope,
                onSearchScopeChange = viewModel::setSearchScope,
                scrollBehavior = scrollBehavior,
            )
        },
    ) { padding ->
        // **Deliberately empty, and named as unfinished rather than filled with a stub.**
        // What belongs here is the at-rest offer — something to continue, something never
        // opened, a next volume — which iOS's `SearchAtRest` already draws and which this side
        // has not been given yet. Section 1 moved search onto a page and section 2 built the
        // bar on it; the page's own content is the piece still outstanding, and saying so here
        // is better than a placeholder that reads as finished.
        //
        // The screen is usable meanwhile: the bar above expands to full screen on a tap and
        // carries the scope chips, recent searches and results.
        Box(modifier = Modifier.fillMaxSize().padding(padding))
    }
}
