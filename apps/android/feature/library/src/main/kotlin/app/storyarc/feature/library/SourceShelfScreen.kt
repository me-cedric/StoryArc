package app.storyarc.feature.library

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.LibraryIndex
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibraryScope
import app.storyarc.core.model.Publication
import java.util.UUID

/**
 * One source's publications, in the library's own arrangement.
 *
 * Lifted beside the screen so the rule is testable on its own, the same reason
 * [seriesShelfMembers] is a free function. [LibraryScope] is what narrows it, so a
 * publication no source claims is left out here by the same rule that leaves it out of the
 * by-library filter.
 *
 * The arrangement is the library's default rather than the reader's current one: this screen
 * carries no sort control and no filter, because it is the library narrowed to one source and
 * not a second library with choices of its own.
 */
fun sourceShelfMembers(sourceId: UUID, publications: List<Publication>): List<Publication> =
    LibraryIndex.arrange(publications, LibraryQuery(scope = LibraryScope.OneSource(sourceId)))

/**
 * Everything one source has put in the library, drawn by the shelf's own grid.
 *
 * `library-browsing`, *More from a source than the library holds*: what a source holds beyond
 * the slice the first read took is reachable from "an explicit *more from this library*
 * affordance at the foot of the shelf", and those publications "are rendered by the same
 * grid, the same cells and the same publication page as everything else". The footer used to
 * open the source's own browser, which draws a catalogue with cells of its own -- the one
 * clause of that scenario the affordance did not meet.
 *
 * **No pager of its own, deliberately.** `ServerLibrary.continueReadingServers` already reads
 * a partial source's later pages and adopts each one as an ordinary library row, so the rest
 * of the library arrives here by itself. Reading the library rather than being handed a list
 * is also what lets a source still answering fill the screen in as it goes, which is the
 * reason [SeriesShelfScreen] reads it too.
 *
 * iOS's `SourceShelfView` is its twin.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun SourceShelfScreen(
    sourceId: UUID,
    title: String,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    onOpenSeries: (String) -> Unit,
    onBack: () -> Unit,
    /**
     * Marks a publication read. The app layer owns the secrets the server may need, so this
     * screen cannot do it alone -- [SeriesShelfScreen] takes the same handler for the same
     * reason. The default exists for the tests.
     */
    onMark: (Publication, Boolean) -> Unit = { _, _ -> },
) {
    val palette = LocalStoryArcPalette.current
    val publications by viewModel.publications.collectAsStateWithLifecycle()
    val members = sourceShelfMembers(sourceId, publications)

    // `library-browsing`: a series "is listed once, as a single cell". The library's own rule,
    // asked here as well, because a cell here and a cell on the shelf have to mean the same
    // thing to a reader who has learned one of them.
    val rows = LibraryRows.of(members)
    val series = rows.filterIsInstance<LibraryRow.Series>().associateBy { it.lead.id }

    var restarting by remember { mutableStateOf<Publication?>(null) }

    // The library's own menu, for the reason *A publication's actions wherever it is drawn*
    // gives: a cell here is the library's cell. No `onRemoveFromShelf` -- a source is where a
    // publication came from, not a shelf the reader assembled, so there is nothing to leave.
    val publicationActions = PublicationActionCallbacks(
        onMark = onMark,
        onRestart = { restarting = it },
        onShowDetails = onOpen,
    )

    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.catalogue_back),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                },
            )
        },
    ) { insets ->
        if (members.isEmpty()) {
            // Not an error: a source that has not answered yet has nothing to list, and the
            // library behind this screen already says the source is still being read.
            Text(
                text = stringResource(R.string.kavita_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
                modifier = Modifier.padding(insets).padding(StoryArcSpace.gutter),
            )
            return@Scaffold
        }
        CoverGrid(
            publications = rows.map { it.lead },
            viewModel = viewModel,
            seriesRows = series,
            onOpenSeries = { onOpenSeries(it.name) },
            onOpen = onOpen,
            actions = publicationActions,
            modifier = Modifier.fillMaxSize().padding(insets),
        )
    }

    // Outside the `Scaffold` for the reason `LibraryScreen` gives: the menu dismisses itself
    // on the way here, so the dialogue cannot hang off the menu that asked for it.
    val restart = restarting
    if (restart != null) {
        RestartConfirmation(
            publication = restart,
            viewModel = viewModel,
            onDismiss = { restarting = null },
        )
    }
}
