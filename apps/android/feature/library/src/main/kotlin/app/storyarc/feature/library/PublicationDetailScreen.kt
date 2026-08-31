package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeFlexibleTopAppBar
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfoV2
import androidx.compose.material3.adaptive.layout.PaneAdaptedValue
import androidx.compose.material3.adaptive.layout.SupportingPaneScaffold
import androidx.compose.material3.adaptive.layout.ThreePaneScaffoldValue
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirective
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication

/** Enough pixels for the largest the cover is ever drawn, on the densest screen. */
private const val DETAIL_COVER_PIXELS = 1200

/**
 * The page a publication has.
 *
 * `publication-detail` calls this the seam, and the word is load-bearing.
 * `library-browsing` presents five kinds of source as one library and takes origin off the
 * shelf entirely — no per-source destinations, no server chips, no source line under a
 * cover. That argument only works because origin is *here*: one line, at the foot of the
 * information, naming where this publication lives and whether it can be opened now. Take
 * this screen away and a reader who owns the same volume locally and on a server cannot
 * tell which one they are about to open.
 *
 * It is also the app's only screen between the shelf and the reader, so everything that is
 * not reading lives here.
 *
 * **Built Material's way, not as a port of the iOS layout.** The direction's divergence
 * register is the authority for each move:
 *
 * - `LargeFlexibleTopAppBar` with a **subtitle**, collapsing onto the cover, rather than a
 *   large title typeset into the content. The delta wants title, series and year to read as
 *   one object; the flexible bars grew a subtitle slot for exactly that (#9).
 * - Emphasis by **shape break and containment**, not by a prominent tinted control — the
 *   register's answer to iOS's `.glassProminent` (#10), and the one that does not tint
 *   artwork.
 * - Secondary actions in an **overflow menu**, with add-to-a-shelf as a **modal bottom
 *   sheet** (#7), which is already the shape this app uses everywhere else.
 * - `SupportingPaneScaffold` for the tablet presentation (#4, #5), so a wide window reads
 *   the series beside the book rather than under it.
 * - Motion from `MaterialTheme.motionScheme` rather than from fixed durations (#11).
 *
 * **Dynamic colour never reaches this page's content.** The direction scopes Material You
 * to chrome, and the delta says the cover's colour "reaches the page's content surfaces
 * only" while "navigation, toolbars and any floating chrome stay as `native-experience`
 * requires". Both rules point the same way and this screen keeps them: the app bar takes
 * Material's own colours and no cover's, and the hero takes the cover's and no wallpaper's.
 * A tinted bar that changed hue as the reader moved between publications is the failure
 * both rules exist to prevent.
 */
@OptIn(
    ExperimentalMaterial3Api::class,
    ExperimentalMaterial3ExpressiveApi::class,
    ExperimentalMaterial3AdaptiveApi::class,
)
@Composable
fun PublicationDetailScreen(
    publication: Publication,
    viewModel: LibraryViewModel,
    /** Whether a copy is on this device — a download, an import, or a file in a scanned folder. */
    isOnDevice: Boolean,
    /** How far a download of this publication has got, or null when none is running. */
    downloadFraction: Float? = null,
    /** Open the book, at the start or where the reader stopped. */
    onRead: (Publication) -> Unit,
    /** Another publication's own page. A cover is the detail verb everywhere in this app. */
    onOpenPage: (Publication) -> Unit,
    onMark: (Publication, Boolean) -> Unit,
    /** Fetch a copy onto the device. Null where the app has no way to fetch this one. */
    onDownload: (() -> Unit)? = null,
    /** Remove the copy on the device. Null where there is none to remove. */
    onRemoveDownload: (() -> Unit)? = null,
    onBack: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val registry by viewModel.registry.collectAsStateWithLifecycle()
    val library by viewModel.publications.collectAsStateWithLifecycle()

    var cover by remember(publication.id) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(publication.id) {
        cover = viewModel.cover(publication, DETAIL_COVER_PIXELS)
    }
    val accent = rememberDetailAccent(cover)

    val provenance = provenanceOf(publication, registry, isOnDevice, library)
    val hasProgress = viewModel.readFraction(publication) != null
    val action = primaryActionOf(publication, provenance, isOnDevice, hasProgress)
    val series = remember(publication.id, library) { restOfSeries(publication, library) }

    // A stale shortcut, a removed source, a deleted file: the publication the page was
    // opened for is no longer anywhere. The delta refuses an empty page for this, and the
    // page has nothing honest to draw, so it says the one true sentence instead.
    //
    // An empty library is *not* an absent publication. The list arrives asynchronously and
    // starts empty, so without this guard every page would claim the book was gone for the
    // frame before the library loaded — and a reader who reached this page from a cover
    // came from a library that had at least that one thing in it.
    val isGone = library.isNotEmpty() && library.none { it.id == publication.id } && !isOnDevice
    if (isGone) {
        DetailGone(onBack = onBack)
        return
    }

    var isMenuOpen by remember { mutableStateOf(false) }
    var isShelfSheetOpen by remember { mutableStateOf(false) }
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        containerColor = palette.surfaceCanvas,
        modifier = Modifier.nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeFlexibleTopAppBar(
                title = { DetailTitle(publication) },
                subtitle = { DetailSubtitle(publication) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.detail_back),
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { isMenuOpen = true }) {
                        Icon(
                            imageVector = Icons.Filled.MoreVert,
                            contentDescription = stringResource(R.string.detail_more),
                        )
                    }
                    DetailOverflowMenu(
                        isOpen = isMenuOpen,
                        onDismiss = { isMenuOpen = false },
                        isFinished = publication.id in viewModel.finishedPublications(),
                        onMark = { isRead -> onMark(publication, isRead) },
                        onAddToShelf = { isShelfSheetOpen = true },
                        onDownload = onDownload,
                        onRemoveDownload = onRemoveDownload,
                    )
                },
                scrollBehavior = scrollBehavior,
            )
        },
    ) { insets ->
        val directive = calculatePaneScaffoldDirective(currentWindowAdaptiveInfoV2())
        val main: @Composable (Modifier) -> Unit = { modifier ->
            DetailMainPane(
                publication = publication,
                cover = cover,
                accent = accent,
                action = action,
                provenance = provenance,
                downloadFraction = downloadFraction,
                onRead = { onRead(publication) },
                onDownload = onDownload,
                modifier = modifier,
            )
        }
        val supporting: @Composable (Modifier) -> Unit = { modifier ->
            DetailSeriesShelf(
                publications = series,
                viewModel = viewModel,
                onOpen = onOpenPage,
                modifier = modifier,
            )
        }

        if (directive.maxHorizontalPartitions > 1) {
            // The delta's "two panes": the series reads beside the book rather than under
            // it. The scaffold, rather than a hand-rolled `Row`, because it is what carries
            // Material's own partition sizes and spacer, and because the same component is
            // what the library will host this page inside once it adopts the list-detail
            // scaffold.
            SupportingPaneScaffold(
                directive = directive,
                value = ThreePaneScaffoldValue(
                    primary = PaneAdaptedValue.Expanded,
                    secondary = PaneAdaptedValue.Expanded,
                    tertiary = PaneAdaptedValue.Hidden,
                ),
                mainPane = { main(Modifier.verticalScroll(rememberScrollState())) },
                supportingPane = { supporting(Modifier.verticalScroll(rememberScrollState())) },
                modifier = Modifier.fillMaxSize().padding(insets),
            )
        } else {
            // One pane, one column, and the series under the book. Not the scaffold with a
            // hidden pane: a hidden supporting pane is a shelf the reader cannot reach, and
            // the shelf is required on every window size.
            Column(
                verticalArrangement = Arrangement.spacedBy(StoryArcSpace.section),
                modifier = Modifier
                    .fillMaxSize()
                    .padding(insets)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.lg),
            ) {
                main(Modifier)
                supporting(Modifier)
            }
        }
    }

    if (isShelfSheetOpen) {
        // Divergence #7: add-to-a-shelf is a modal bottom sheet on Android and a menu on
        // iOS, and both are the platform-idiomatic shape. The sheet already exists and
        // already carries mark-read, so this page grew no second copy of either.
        AddToShelfSheet(
            viewModel = viewModel,
            publications = listOf(publication),
            onDismiss = { isShelfSheetOpen = false },
            onMark = { publications, isRead -> publications.forEach { onMark(it, isRead) } },
        )
    }
}

/**
 * Everything about the book itself: the cover over its colour, the one action, what it is,
 * and where it came from.
 *
 * The provenance line is last, quiet, and at the foot of the information — which is where
 * the delta puts it and why every other browse surface is allowed to say nothing about
 * origin at all.
 */
@Composable
private fun DetailMainPane(
    publication: Publication,
    cover: Bitmap?,
    accent: DetailAccent?,
    action: PrimaryAction,
    provenance: Provenance,
    downloadFraction: Float?,
    onRead: () -> Unit,
    onDownload: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.lg),
    ) {
        DetailHero(publication = publication, cover = cover, accent = accent) {
            DetailPrimaryAction(
                action = action,
                accent = accent,
                onRead = onRead,
                onDownload = onDownload,
            )
        }

        // `offline-downloads` allows reading while downloading, so this is progress rather
        // than a gate: the primary action above stays exactly as usable as it was.
        downloadFraction?.let { fraction ->
            Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs)) {
                Text(
                    text = stringResource(R.string.detail_downloading),
                    style = MaterialTheme.typography.labelMedium,
                    color = palette.textSecondary,
                )
                LinearProgressIndicator(
                    progress = { fraction },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        publication.summary?.takeIf { it.isNotBlank() }?.let { summary ->
            Text(
                text = summary,
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
            )
        }

        ProvenanceLine(provenance)
    }
}

/**
 * The one thing the page wants the reader to do, and a sentence when it cannot.
 *
 * First control after the title in the reading order, which the design's accessibility note
 * calls an accessibility feature rather than a layout preference: its label says which of
 * *read* and *continue* will happen, so a screen-reader user learns the outcome before
 * taking it.
 */
@Composable
private fun DetailPrimaryAction(
    action: PrimaryAction,
    accent: DetailAccent?,
    onRead: () -> Unit,
    onDownload: (() -> Unit)?,
) {
    val palette = LocalStoryArcPalette.current
    val scheme = MaterialTheme.colorScheme
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
    ) {
        val press: (() -> Unit)? = when {
            action.opensTheBook -> onRead
            action == PrimaryAction.REFUSED -> null
            else -> onDownload
        }
        if (press != null) {
            Button(
                onClick = press,
                shape = MaterialTheme.shapes.large,
                colors = ButtonDefaults.buttonColors(
                    // The cover's own accent, already adjusted until it clears the 3:1
                    // floor against the wash it is drawn on — never the raw extracted
                    // colour, which the delta forbids outright. The brand accent where the
                    // cover yielded nothing, which is `native-experience`'s answer for a
                    // surface with no publication colour of its own.
                    containerColor = accent?.accent ?: scheme.primary,
                    contentColor = accent?.onAccent ?: scheme.onPrimary,
                ),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(action.label()))
            }
        }
        action.explanation()?.let { explanation ->
            Text(
                text = stringResource(explanation),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
    }
}

/**
 * Everything that is not reading.
 *
 * `publication-detail`: each of these is "available from this page without competing with
 * the primary action", and "an action that does not apply is absent, not shown disabled
 * without explanation". So download and remove-download are `null` rather than greyed when
 * the app has no way to perform them.
 */
@Composable
private fun DetailOverflowMenu(
    isOpen: Boolean,
    onDismiss: () -> Unit,
    isFinished: Boolean,
    onMark: (Boolean) -> Unit,
    onAddToShelf: () -> Unit,
    onDownload: (() -> Unit)?,
    onRemoveDownload: (() -> Unit)?,
) {
    DropdownMenu(expanded = isOpen, onDismissRequest = onDismiss) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.detail_add_to_shelf)) },
            onClick = {
                onDismiss()
                onAddToShelf()
            },
        )
        DropdownMenuItem(
            text = {
                Text(
                    stringResource(
                        if (isFinished) R.string.library_mark_unread else R.string.library_mark_read,
                    ),
                )
            },
            onClick = {
                onDismiss()
                onMark(!isFinished)
            },
        )
        onDownload?.let { download ->
            DropdownMenuItem(
                text = { Text(stringResource(R.string.detail_action_download)) },
                onClick = {
                    onDismiss()
                    download()
                },
            )
        }
        onRemoveDownload?.let { remove ->
            DropdownMenuItem(
                text = { Text(stringResource(R.string.downloads_remove)) },
                onClick = {
                    onDismiss()
                    remove()
                },
            )
        }
    }
}

/**
 * The publication the page was opened for is not there any more.
 *
 * The delta asks for the reader to be returned "with a plain sentence saying it is gone".
 * The shell has no snackbar host above a destination's screens, so returning *and* saying
 * it would mean inventing one here — which is the app layer's business and another slice's
 * file. One plain sentence and the way back is the honest half of that, and it is still
 * emphatically not an empty page. The handoff records the rest.
 */
@Composable
private fun DetailGone(onBack: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Column(
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        modifier = Modifier.fillMaxSize().padding(StoryArcSpace.xxl),
    ) {
        Text(
            text = stringResource(R.string.detail_gone_title),
            style = MaterialTheme.typography.headlineSmall,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(R.string.detail_gone_body),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )
        Button(onClick = onBack, modifier = Modifier.padding(top = 8.dp)) {
            Text(stringResource(R.string.detail_gone_back))
        }
    }
}

/**
 * The second pane, before a publication has been chosen.
 *
 * `publication-detail`: "the second pane says so in one sentence rather than showing an
 * arbitrary publication or an empty rectangle". Both of the things it forbids are worse
 * than they sound — an arbitrary publication is the app claiming the reader chose
 * something, and an empty rectangle is half a tablet of nothing with nothing said about it.
 *
 * Android had a third answer, which was to hide the pane until something went in it. It is
 * out because the shelf reflowed when the pane arrived: the column count changed under the
 * reader on their first tap and changed back on their last press of Back, which is the
 * library rearranging itself in answer to something that was not about the library. §4.7 of
 * the direction settles it from the other side — "expanded and above: two panes" — and a
 * pane that is only sometimes there is not two panes.
 *
 * The wording is iOS's, to the word, in the four languages the app speaks. One situation
 * described twice is how a four-language app comes apart, and this is one situation.
 */
@Composable
fun PublicationPanePlaceholder(modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = modifier.fillMaxSize().padding(StoryArcSpace.xxl),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = stringResource(R.string.detail_pane_empty),
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textSecondary,
        )
    }
}
