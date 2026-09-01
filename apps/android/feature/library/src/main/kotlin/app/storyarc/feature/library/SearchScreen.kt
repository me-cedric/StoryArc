package app.storyarc.feature.library

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
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
    /**
     * The three ways in that open a sheet only the app layer can put up.
     *
     * Here for `navigation-shell`'s *Nothing to suggest*, which asks the search page for "the
     * same way of adding a source that the library's own empty state offers" — and that state
     * offers five. `LibraryScreen` takes the identical three from the identical host.
     */
    onAddCatalogue: () -> Unit,
    onAddKavita: () -> Unit,
    onAddShare: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current
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

    val publications by viewModel.publications.collectAsStateWithLifecycle()
    val registry by viewModel.registry.collectAsStateWithLifecycle()

    /**
     * What the page offers before a letter is typed.
     *
     * `derivedStateOf` rather than a plain `remember`, and the difference is a defect either
     * way round. The offer is a function of three things: the library, the registry, and the
     * reading records — and the records are a snapshot map the model writes into as they
     * reload, which no `remember` key can name. A keyed `remember` would hold the first answer
     * for ever and a reader back from the reader would find *Pick up where you left off*
     * unchanged; no `remember` at all would recompute the whole offer on every frame of a
     * scroll. The derived state reads the map, so it recomputes exactly when it moves.
     *
     * The keys are still the library and the registry, so the derived state itself is rebuilt
     * when a scan replaces the list.
     *
     * `isReadableNow` is the library's own answer and not this screen's. Home asked it
     * itself once and got both of the two mistakes the shared rule was written to prevent —
     * see `HomeDestination`, which photographed the result on an emulator.
     */
    val suggestions by remember(publications, registry) {
        derivedStateOf {
            SearchSuggestions.of(
                publications = publications,
                progress = viewModel::recordOf,
                isReadableNow = viewModel::isReadableNow,
            )
        }
    }

    // The two of the five ways in that need nothing but a system picker. `sources` makes
    // opening a comic the primary action — it "opens a comic from the device with nothing to
    // configure first" — and a folder is the one kind of library that needs no address and no
    // credentials. `LibraryScreen` builds the identical pair for the shelf's own empty state;
    // the persistable grant can only be taken here, with the result in hand. The other three
    // arrive as parameters, because each opens a sheet the app layer owns.
    val importFile = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { file -> if (file != null) viewModel.importFile(file) }

    val pickFolder = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree(),
    ) { tree ->
        if (tree != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            viewModel.addFolder(tree)
        }
    }

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
        SearchAtRest(
            suggestions = suggestions,
            scope = scope,
            onScopeChange = viewModel::setSearchScope,
            cover = viewModel::cover,
            // A cover leads to the publication's own page, never straight into the reader:
            // `publication-detail` makes the two different verbs, and a suggestion is a cover
            // like any other. Home's Keep reading card is the one place that resumes.
            onOpenPage = onOpenPage,
            onOpenComic = { importFile.launch(arrayOf("*/*")) },
            onAddFolder = { pickFolder.launch(null) },
            onAddCatalogue = onAddCatalogue,
            onAddKavita = onAddKavita,
            onAddShare = onAddShare,
            modifier = Modifier.fillMaxSize().padding(padding),
        )
    }
}
