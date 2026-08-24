package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.IconButton
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.flow.MutableStateFlow
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind

/**
 * The library. At this stage it renders the empty state and the source list —
 * the two surfaces `sources` requires before any content exists.
 *
 * Cover grid, search, filtering and sorting land with the `library-browsing`
 * capability; this is the shell they hang off.
 */
/**
 * The library.
 *
 * Three states, in the order a user meets them: nothing added, a scan running, and
 * a grid of covers. Search, filtering and sorting are the rest of
 * `library-browsing` and are not here yet.
 *
 * `viewModel` is nullable so previews and the empty-state tests can render without
 * an Application — the screen is otherwise identical either way.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(
    sources: List<Source> = emptyList(),
    viewModel: LibraryViewModel? = null,
    /**
     * How the app layer reaches the reader. The library knows which publication
     * was chosen and where it lives; it does not know what a reader is.
     */
    onOpen: (Publication, java.io.File) -> Unit = { _, _ -> },
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val publications by (viewModel?.publications ?: MutableStateFlow(emptyList()))
        .collectAsStateWithLifecycle()
    val scanState by (viewModel?.scanState ?: MutableStateFlow(LibraryScanState.Idle))
        .collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier,
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.library_title)) },
                actions = {
                    if (viewModel != null) {
                        IconButton(onClick = { viewModel.scan() }) {
                            Icon(
                                imageVector = Icons.Filled.Refresh,
                                contentDescription = stringResource(
                                    R.string.library_scan_folder,
                                ),
                                tint = palette.accent,
                            )
                        }
                    }
                },
            )
        },
        bottomBar = {
            val state = scanState
            if (state is LibraryScanState.Finished && state.skipped > 0) {
                // Stated once, at the end, rather than per file — a messy folder
                // would otherwise be a wall of notices. But stated: a count that
                // silently omits what it could not read is a lie.
                Text(
                    text = stringResource(R.string.library_skipped, state.skipped),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.sm),
                )
            }
        },
    ) { insets ->
        Box(
            modifier = Modifier.fillMaxSize().padding(insets),
            contentAlignment = Alignment.Center,
        ) {
            val state = scanState
            when {
                publications.isNotEmpty() && viewModel != null ->
                    CoverGrid(
                        publications = publications,
                        viewModel = viewModel,
                        onOpen = { publication ->
                            viewModel.location(publication)?.let { onOpen(publication, it) }
                        },
                    )

                state is LibraryScanState.Scanning -> Scanning(state.found)
                sources.isEmpty() -> EmptyLibrary(onScan = { viewModel?.scan() })
                else -> SourceList(sources)
            }
        }
    }
}

/**
 * While a scan runs.
 *
 * `local-library` requires progress reported as a count of items found, and
 * requires that browsing what is already found is not blocked — so this is only
 * ever seen before the first publication arrives.
 */
@Composable
private fun Scanning(found: Int, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        CircularProgressIndicator(color = palette.accent)
        Text(
            text = stringResource(R.string.library_scanning, found),
            style = MaterialTheme.typography.bodySmall,
            color = palette.textSecondary,
        )
    }
}

/**
 * `sources`: an empty library names the four source types with a one-line
 * explanation of each. Never an illustration with no action — see DESIGN.md §9.
 */
@Composable
private fun EmptyLibrary(onScan: () -> Unit = {}, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current

    Column(
        modifier = modifier
            .widthIn(max = StoryArcSpace.huge * 8)
            .padding(horizontal = StoryArcSpace.gutter),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xl),
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            Text(
                text = stringResource(R.string.library_empty_title),
                style = MaterialTheme.typography.headlineMedium,
                color = palette.textPrimary,
            )
            Text(
                text = stringResource(R.string.library_empty_subtitle),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
                textAlign = TextAlign.Center,
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
            SourceKind.entries.forEach { kind -> SourceKindRow(kind) }
        }

        // `sources` requires the empty state to offer an action rather than only
        // describe one — see DESIGN.md §9.
        Button(onClick = onScan, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.library_scan_folder))
        }
    }
}

@Composable
private fun SourceKindRow(kind: SourceKind, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current

    Surface(
        modifier = modifier.fillMaxWidth(),
        color = palette.surfaceRaised,
        shape = RoundedCornerShape(StoryArcRadius.lg),
    ) {
        Row(
            modifier = Modifier
                .padding(StoryArcSpace.md)
                // Material's 48 dp touch-target floor, per `native-experience`.
                .heightIn(min = StoryArcSpace.xxl + StoryArcSpace.lg),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = kind.icon,
                contentDescription = null,
                tint = palette.accent,
            )
            // Tight stack: title and explanation read as one object, per the
            // uneven-rhythm rule in DESIGN.md §4.
            Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair)) {
                Text(
                    text = stringResource(kind.titleRes),
                    style = MaterialTheme.typography.titleMedium,
                    color = palette.textPrimary,
                )
                Text(
                    text = stringResource(kind.explanationRes),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textSecondary,
                )
            }
        }
    }
}

@Composable
private fun SourceList(sources: List<Source>, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(StoryArcSpace.gutter),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        items(sources, key = { it.id }) { source ->
            Surface(
                // An offline source is dimmed, never reddened — offline is normal.
                modifier = Modifier.fillMaxWidth().alpha(if (source.state.canFetch) 1f else 0.55f),
                color = palette.surfaceRaised,
                shape = RoundedCornerShape(StoryArcRadius.lg),
            ) {
                Row(
                    modifier = Modifier.padding(StoryArcSpace.md),
                    horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(source.kind.icon, contentDescription = null, tint = palette.accent)

                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
                    ) {
                        Text(
                            text = source.displayName,
                            style = MaterialTheme.typography.bodyLarge,
                            color = palette.textPrimary,
                        )
                        // Colour is never the only signal: the state is spelled
                        // out here as well as carried by the dot beside it.
                        Text(
                            text = stringResource(source.state.statusRes),
                            style = MaterialTheme.typography.labelLarge,
                            color = palette.textTertiary,
                        )
                    }

                    Surface(
                        modifier = Modifier.size(StoryArcSpace.sm),
                        shape = CircleShape,
                        color = source.state.indicatorColor(palette),
                        content = {},
                    )
                }
            }
        }
    }
}

@Preview(name = "Empty library — dark")
@Composable
private fun LibraryScreenEmptyPreview() {
    StoryArcTheme(useDynamicColor = false) { LibraryScreen() }
}
