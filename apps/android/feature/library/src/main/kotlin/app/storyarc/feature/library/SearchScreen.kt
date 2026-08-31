package app.storyarc.feature.library

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
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
 * `Scaffold` for the window insets alone: the navigation shell has taken the bottom one and
 * the status bar is still to pay for. The canvas rather than Material's surface, per the
 * colour rule — dynamic colour is scoped to chrome and kept off the artwork.
 */
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

    Scaffold(
        modifier = modifier.fillMaxSize(),
        containerColor = palette.surfaceCanvas,
        topBar = {
            LibrarySearchEntry(
                viewModel = viewModel,
                query = query,
                recents = recents,
                onOpenPage = onOpenPage,
                onFollowToSource = onFollowToSource,
            )
        },
    ) { padding ->
        // **Deliberately empty, and named as unfinished rather than filled with a stub.**
        // What belongs here is the at-rest offer — something to continue, something never
        // opened, a next volume — and that is section 2 of `quiet-shell-and-search`, which
        // has its own requirement and its own tests. Section 1 moves search onto a page; it
        // does not get to claim the page's content.
        //
        // The screen is usable meanwhile: the bar above expands to full screen on a tap and
        // carries recent searches and results exactly as it did on the shelf.
        Box(modifier = Modifier.fillMaxSize().padding(padding))
    }
}
