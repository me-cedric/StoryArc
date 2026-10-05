package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
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
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationStatus

/**
 * A series' own publications, in the library's `SERIES` order.
 *
 * Lifted beside the screen so the ordering rule is testable on its own: `library-browsing`
 * says an opened series lists its issues "in their own order", and that order is the
 * library's `SERIES` comparison (number, then natural filename), not adoption order.
 */
fun seriesShelfMembers(name: String, publications: List<Publication>): List<Publication> =
    LibraryIndex.arrange(
        publications.filter { it.series == name },
        LibraryQuery(sort = LibrarySort.SERIES),
    )

/**
 * One series, and the publications inside it.
 *
 * `library-browsing`: "when a reader opens a series, then its publications are listed in
 * their own order, each openable, each carrying the marks a cover carries in the grid", and
 * "one gesture returns to the library, at the place the reader left it".
 *
 * The same grid the library draws, given one series' members: a cell here and a cell there
 * must be the same thing, because a reader who has learned what a cover means in the library
 * has learned it here too. That is also why this screen has no sections, no sort control and
 * no filter -- a series is already the answer to all three.
 *
 * The members are read from the library rather than passed in, so a series opened before a
 * source finished answering fills in as the rest arrives.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun SeriesShelfScreen(
    name: String,
    viewModel: LibraryViewModel,
    onOpen: (Publication) -> Unit,
    onBack: () -> Unit,
    /**
     * Marks a publication read. The app layer owns the secrets the server may need, so this
     * screen cannot do it alone -- [CollectionDetailScreen] takes the same handler for the
     * same reason.
     *
     * The default exists for the tests. A caller that takes it leaves the menu's *Mark as
     * read* row doing nothing, so every caller that has a view model must pass one.
     */
    onMark: (Publication, Boolean) -> Unit = { _, _ -> },
) {
    val palette = LocalStoryArcPalette.current
    val publications by viewModel.publications.collectAsStateWithLifecycle()
    val members = seriesShelfMembers(name, publications)

    var restarting by remember { mutableStateOf<Publication?>(null) }

    // `library-browsing`'s *A publication's actions wherever it is drawn*: a cell here is the
    // library's own cell, so it has to offer the library's own menu. This screen drew the grid
    // without one, which left a series the single place a long press did nothing.
    //
    // No `onRemoveFromShelf`: a series is what the publications say they are, not a shelf the
    // reader assembled, so there is nothing here to leave. That row is withheld rather than
    // drawn dead, which is the same rule the status menu above follows.
    val publicationActions = PublicationActionCallbacks(
        onMark = onMark,
        onRestart = { restarting = it },
        onShowDetails = onOpen,
    )

    Scaffold(
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = { Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.catalogue_back),
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                },
                actions = {
                    // D36: "a status a source reports is not editable by the reader -- only
                    // a series with no reported status takes one set by hand". Withheld
                    // entirely for a reported series rather than shown disabled, the same
                    // rule `design.md` gives every other control that would change nothing.
                    if (!viewModel.seriesHasReportedStatus(name)) {
                        SeriesStatusMenu(name, viewModel)
                    }
                },
            )
        },
    ) { insets ->
        if (members.isEmpty()) {
            // Not an error: a series whose source has not answered yet has no members to
            // list, and the library says elsewhere that the source is still being read.
            Text(
                text = stringResource(R.string.kavita_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
                modifier = Modifier.padding(insets).padding(StoryArcSpace.gutter),
            )
            return@Scaffold
        }
        Column(
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            modifier = Modifier.fillMaxSize().padding(insets),
        ) {
            Box(modifier = Modifier.padding(horizontal = StoryArcSpace.gutter)) {
                ShelfOnDeviceLine(members, location = viewModel::location)
            }
            CoverGrid(
                publications = members,
                viewModel = viewModel,
                onOpen = onOpen,
                actions = publicationActions,
                modifier = Modifier.weight(1f),
            )
        }
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

/** The status a reader sets by hand, for a series with no reported one. */
@Composable
private fun SeriesStatusMenu(name: String, viewModel: LibraryViewModel) {
    var open by remember { mutableStateOf(false) }
    val current = viewModel.manualStatus(name)

    Box {
        IconButton(onClick = { open = true }) {
            Icon(
                imageVector = Icons.Filled.Sell,
                contentDescription = stringResource(R.string.library_series_status),
            )
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            PublicationStatus.entries.forEach { status ->
                DropdownMenuItem(
                    text = { Text(stringResource(status.labelRes)) },
                    leadingIcon = if (status == current) {
                        { Icon(Icons.Filled.Check, contentDescription = null) }
                    } else {
                        null
                    },
                    onClick = {
                        viewModel.setSeriesStatus(name, status)
                        open = false
                    },
                )
            }
            if (current != null) {
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.library_series_status_clear)) },
                    onClick = {
                        viewModel.clearSeriesStatus(name)
                        open = false
                    },
                )
            }
        }
    }
}
