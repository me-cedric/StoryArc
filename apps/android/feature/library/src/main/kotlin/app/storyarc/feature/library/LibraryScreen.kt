package app.storyarc.feature.library

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.theme.rememberWindowClass
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.BulkSelection
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibraryScope
import app.storyarc.core.model.MatchGroup
import app.storyarc.core.model.Publication
import app.storyarc.core.model.RecentSearches
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * The library — the exhaustive shelf, and only that.
 *
 * Four states, in the order a reader meets them: nothing added, a walk running, a shelf
 * narrowed to nothing, and the covers themselves. What used to be a bar of eight icons is
 * now a flexible bar with an overflow menu ([LibraryTopBar]) and a chip row of the controls
 * a reader actually touches ([LibraryControls]) — see `LibraryTopBar`'s own note for the
 * defect that forced it.
 *
 * `viewModel` is nullable so previews and the empty-state tests can render without
 * an Application — the screen is otherwise identical either way.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(
    viewModel: LibraryViewModel? = null,
    /**
     * How the app layer reaches the reader. The library knows which publication
     * was chosen and where it lives; it does not know what a reader is.
     */
    onOpen: (Publication, String) -> Unit = { _, _ -> },
    /**
     * How the app layer reaches a publication's own page.
     *
     * The other verb `publication-detail` requires: "a publication's page SHALL be
     * reachable from every surface that shows a publication, and SHALL be distinguished
     * from resuming, which opens the book directly". Every cover on this screen — the grid,
     * the list and the search results — calls this. [onOpen] is left to the one affordance
     * that offers to resume, the continue-reading row.
     */
    onOpenPage: (Publication) -> Unit = {},
    /**
     * How the app layer reaches Settings.
     *
     * The library does not know what a settings screen is, for the same reason it does
     * not know what a reader is: a feature module never depends on another feature
     * module. It reports that the reader asked.
     */
    onOpenSettings: () -> Unit = {},
    /**
     * How the app layer reaches a library that is not on this device.
     *
     * No longer reached from a strip of chips above the shelf — those went with the
     * per-source destinations — but still the one rule that decides what an unreachable or
     * refused source leads to, which is what [onFollowToSource] falls back to. Same
     * reasoning as `onOpen`: the library knows which library was chosen and does not know
     * what a browser is.
     */
    onBrowse: (Source) -> Unit = {},
    /**
     * Reaching a library that is not on this device, carrying the term that was searched.
     *
     * Defaults to [onBrowse] and drops the term: opening the library is the part that
     * matters, and an app layer that has not been taught to carry the term yet should still
     * get the reader there rather than nowhere.
     */
    onFollowToSource: (Source, String) -> Unit = { source, _ -> onBrowse(source) },
    /**
     * Puts a running search to the server the library is filtered to.
     *
     * `kavita-server` asks a search within a Kavita source to reach the server; the field
     * above filters the local index, and this is the way across.
     */
    onSearchOnServer: (Source, String) -> Unit = { _, _ -> },
    /** Opens the add-a-catalogue sheet, which the app layer hosts. */
    onAddCatalogue: () -> Unit = {},
    /** Opens the collections screen, which the app layer hosts. */
    onOpenShelves: () -> Unit = {},
    /** Opens the add-a-Kavita-server sheet, which the app layer hosts. */
    onAddKavita: () -> Unit = {},
    /** Opens the add-a-network-share sheet, which the app layer hosts. */
    onAddShare: () -> Unit = {},
    /** Asks every network source whether it is there. The app layer owns the secrets. */
    onProbeSources: () -> Unit = {},
    /** Marks a publication read or unread. The app layer owns the secrets it may need. */
    onMark: (Publication, Boolean) -> Unit = { _, _ -> },
    /** Adds to one of a server's reading lists. False when that server cannot hold it. */
    onAddToServerList: (suspend (Publication, ServerList) -> Boolean)? = null,
    /**
     * A download removed because the reader finished it, and how to put it back.
     *
     * `offline-downloads`: the removal "is undoable for 10 seconds". Held by the app layer,
     * which owns the file, and shown here because this is the screen a reader lands on when
     * the reader closes.
     */
    removedDownload: String? = null,
    onUndoRemoval: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current

    // The one input to the layout, and it is the window's own: no device check, no
    // posture check. When it says there is room, the app layer is drawing a navigation
    // rail beside this screen, and the two ways in that the rail already shows -- shelves
    // and settings -- come off the overflow menu rather than being offered twice.
    val windowClass = rememberWindowClass()

    // Hide-on-scroll, not pinned. `native-experience` asks for a scroll edge effect where
    // content meets chrome; on Material that is the flexible bar collapsing as the shelf
    // passes under it, which is Android's answer to getting chrome out of the artwork's
    // way. The controls a reader needs mid-scroll do not go with it -- they sit below the
    // bar in their own row, which is the whole point of moving them out of it.
    val topBarScroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    /** The publication whose add-to-shelf sheet is open, if any. */
    var shelving by remember { mutableStateOf<Publication?>(null) }
    var restarting by remember { mutableStateOf<Publication?>(null) }

    /**
     * What the reader has picked, when they are picking.
     *
     * `collections-and-reading-lists`: publications "can be selected in bulk from the
     * library". Held here rather than in either layout, because the reader may switch
     * between the grid and the list mid-selection and should not lose what they picked.
     */
    var selection by remember { mutableStateOf(LibrarySelection()) }
    /** Whether the add-to sheet is open over the whole selection rather than one cover. */
    var isShelvingSelection by remember { mutableStateOf(false) }
    /** The last bulk action, until its ten seconds are up. */
    var undo by remember { mutableStateOf<BulkUndo?>(null) }

    /**
     * The library's primary axis: everything, or only what can be read with no network.
     *
     * Saved rather than remembered, so a rotation or a trip through the reader comes back
     * to the shelf the reader left. It does not yet survive a cold start: the query is what
     * `LibraryPreferences` persists and availability is not part of it — see
     * [LibraryAvailability] and the handoff.
     */
    var availability by rememberSaveable { mutableStateOf(LibraryAvailability.EVERYTHING) }

    /**
     * The download group of the filter, which is a facet rather than an axis.
     *
     * Beside [availability] and not inside it: [DownloadFilter] sets out why the two are
     * different questions. Saved the same way, and with the same limit — the query is what
     * `LibraryPreferences` persists and neither of these is part of it, so both come back
     * after a rotation and neither survives a cold start yet.
     */
    var downloads by rememberSaveable { mutableStateOf(DownloadFilter.EITHER) }

    // Android hands a picked folder over as a tree `Uri` and grants access to it
    // only for this process — until the app asks for the grant to be persisted,
    // which can only be done here, with the result in hand. That single call is
    // what makes `local-library`'s "reachable after a device restart" true.
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
            viewModel?.addFolder(tree)
        }
    }

    // `sources` asks for "a single unobtrusive indicator" saying that content is cached and
    // when it was last refreshed. It leaves as soon as a walk finishes: at that point the
    // shelf is not cached, it is current, and a notice still claiming otherwise would be the
    // indicator lying quietly in the corner. iOS shows the same line above its grid.
    val cachedAt by (viewModel?.cachedAt ?: MutableStateFlow(null)).collectAsStateWithLifecycle()

    // Everything, rather than a list of comic types. A provider resolves `.cbz` through
    // `MimeTypeMap`, which has never heard of it, so it answers `application/octet-stream` --
    // a filter naming the comic types would grey out every comic on the device. The refusal
    // below is what actually decides, and it names the format it refused.
    val importFile = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { file -> if (file != null) viewModel?.importFile(file) }

    LaunchedEffect(viewModel) {
        viewModel?.restoreFolders()
        // So a publication downloaded from a server joins the one library, rather than being
        // reachable only by browsing back to the server it came from.
        viewModel?.adoptDownloads()
        onProbeSources()
    }

    // The retry loop runs in the view model's scope, which outlives this screen, so it has
    // to be told when nobody is looking. iOS needs no equivalent: its loop runs from a
    // `task` modifier and is cancelled with the view.
    DisposableEffect(viewModel) {
        onDispose { viewModel?.stopRetrying() }
    }

    // On resume, not on first composition. The comic reader is a composable in the
    // same activity and the EPUB reader is an activity of its own, so "the reader
    // closed" reaches this screen two different ways — and only one of them
    // recomposes it. Resuming covers both.
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        viewModel?.refreshProgress()
        // Settings is where an imported copy is deleted, and a library that only read the
        // store at startup would keep offering a book whose bytes are gone.
        viewModel?.refreshImports()
        // `local-library`: on returning to the foreground the app "reconciles by comparing
        // file modification times and sizes rather than re-reading every archive". The
        // watcher covers the app being on screen; a provider notifies nobody while it is not.
        viewModel?.reconcileWatchedFolders()
    }
    val publications by (viewModel?.publications ?: MutableStateFlow(emptyList()))
        .collectAsStateWithLifecycle()
    val scanState by (viewModel?.scanState ?: MutableStateFlow(LibraryScanState.Idle))
        .collectAsStateWithLifecycle()
    val unavailable by (viewModel?.unavailableFolders ?: MutableStateFlow(emptyList<String>()))
        .collectAsStateWithLifecycle()
    val visible by (viewModel?.visible ?: MutableStateFlow(emptyList<Publication>()))
        .collectAsStateWithLifecycle()
    val continueReading by (viewModel?.continueReading ?: MutableStateFlow(emptyList<Publication>()))
        .collectAsStateWithLifecycle()
    val registry by (viewModel?.registry ?: MutableStateFlow(SourceRegistry()))
        .collectAsStateWithLifecycle()
    val query by (viewModel?.query ?: MutableStateFlow(LibraryQuery()))
        .collectAsStateWithLifecycle()
    val layout by (viewModel?.layout ?: MutableStateFlow(LibraryLayout.GRID))
        .collectAsStateWithLifecycle()
    val recentSearches by (viewModel?.recentSearches ?: MutableStateFlow(RecentSearches()))
        .collectAsStateWithLifecycle()

    // Named, not swallowed. `local-library` forbids a generic failure elsewhere and there is
    // no reason an import should be the exception.
    val importFailure by (viewModel?.importFailure ?: MutableStateFlow<String?>(null))
        .collectAsStateWithLifecycle()
    importFailure?.let { name ->
        AlertDialog(
            onDismissRequest = { viewModel?.dismissImportFailure() },
            title = { Text(stringResource(R.string.library_import_failed_title)) },
            text = { Text(stringResource(R.string.library_import_failed, name)) },
            confirmButton = {
                TextButton(onClick = { viewModel?.dismissImportFailure() }) {
                    Text(stringResource(R.string.library_import_dismiss))
                }
            },
        )
    }
    val groups by (viewModel?.matchGroups ?: MutableStateFlow(emptyList<MatchGroup>()))
        .collectAsStateWithLifecycle()

    // The shelf as the primary axis and the download group leave it. One pass each over an
    // already-sorted list, so narrowing and widening never re-orders what the reader is
    // looking at.
    val shown = remember(visible, availability, downloads, registry, viewModel) {
        visible
            .narrowedTo(availability, registry)
            .narrowedTo(downloads) { viewModel?.isOnDevice(it) == true }
    }

    val snackbars = remember { SnackbarHostState() }
    val undoLabel = stringResource(R.string.downloads_undo)
    val removedMessage = removedDownload?.let {
        stringResource(R.string.downloads_removed_after_finishing, it)
    }
    LaunchedEffect(removedMessage) {
        val message = removedMessage ?: return@LaunchedEffect
        // Ten seconds, which is what the spec promises, rather than the platform's default
        // few. A reader who has just closed a book is not looking at the library yet.
        val answer = snackbars.showSnackbar(
            message = message,
            actionLabel = undoLabel,
            duration = SnackbarDuration.Indefinite,
        )
        if (answer == SnackbarResult.ActionPerformed) onUndoRemoval()
    }

    BulkUndoEffect(undo, snackbars, viewModel, publications, onMark) { undo = null }

    Scaffold(
        modifier = modifier.nestedScroll(topBarScroll.nestedScrollConnection),
        containerColor = palette.surfaceCanvas,
        snackbarHost = { SnackbarHost(snackbars) },
        topBar = {
            LibraryTopBar(
                scrollBehavior = topBarScroll,
                onAddFolder = { pickFolder.launch(null) },
                onAddCatalogue = onAddCatalogue,
                onAddKavita = onAddKavita,
                onAddShare = onAddShare,
                onImport = { importFile.launch(arrayOf("*/*")) },
                // The way in. The way out is in the bar the selection puts up, so the
                // menu does not gain an entry that is only half useful.
                onSelect = if (viewModel != null && publications.isNotEmpty() &&
                    !selection.isActive
                ) {
                    { selection = selection.begin() }
                } else {
                    null
                },
                // A wide window already shows both of these as rail items, and a menu that
                // repeated them would be two ways to one place.
                onOpenShelves = if (windowClass.showsSidebar) null else onOpenShelves,
                onOpenSettings = if (windowClass.showsSidebar) null else onOpenSettings,
            )
        },
        bottomBar = {
            val state = scanState
            if (selection.isActive && viewModel != null) {
                BulkActionBar(
                    viewModel = viewModel,
                    selection = selection,
                    onSelectionChange = { selection = it },
                    onAddToShelf = { isShelvingSelection = true },
                    onMarkRead = {
                        val changing = BulkSelection.marking(
                            selection.ids,
                            read = true,
                            finished = viewModel.finishedPublications(),
                        )
                        publications.filter { it.id in changing }.forEach { onMark(it, true) }
                        undo = BulkUndo(BulkUndo.Kind.Read(true), changing)
                    },
                    onChange = { undo = it },
                )
            } else if (unavailable.isNotEmpty()) {
                UnavailableFolders(
                    names = unavailable,
                    onRepick = { pickFolder.launch(null) },
                )
            } else if (state is LibraryScanState.Finished && state.skipped > 0) {
                // Stated once, at the end, rather than per file — a messy folder
                // would otherwise be a wall of notices. But stated: a count that
                // silently omits what it could not read is a lie.
                //
                // Secondary, like the other three branches of this bar. Tertiary is the
                // tone for a line beside something louder, and this strip holds one thing
                // at a time — a notice that is the only content of its own bar is not
                // subordinate to anything. iOS's equivalent moved to secondary for the
                // readability of a notice under translucent chrome; Compose's `bottomBar`
                // is opaque and the shelf is inset above it, so this is the consistency
                // half of that change rather than the contrast half.
                Text(
                    text = stringResource(R.string.library_skipped, state.skipped),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textSecondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.sm),
                )
            }
        },
    ) { insets ->
        Column(modifier = Modifier.fillMaxSize().padding(insets)) {
            // No strip of per-source chips above the shelf. `library-browsing` presents
            // every source as one library and takes origin off the browse path entirely, and
            // task 2.4 of `one-library-three-destinations` asked for the chips to go with
            // the per-source destinations. A reader who wants a server's own pages reaches
            // it from Settings, where the connection lives. iOS removed its equivalent in
            // the same slice.

            KavitaSearchOffer(registry, query, onSearchOnServer)

            // Above the refreshable area, not inside it: pulling on a search field means
            // nothing, and an indicator that comes down over the controls hides the two
            // chips saying what the shelf underneath is narrowed to.
            if (viewModel != null && publications.isNotEmpty()) {
                // One bar, above the branch rather than inside it. The branch below changes
                // as the reader types — a term that matches nothing swaps the shelf for the
                // narrowed-to-nothing state — and a bar built inside it was rebuilt with the
                // branch: it collapsed itself, and every remote answer that had arrived went
                // with it.
                LibrarySearchEntry(
                    viewModel = viewModel,
                    query = query,
                    recents = recentSearches,
                    onOpenPage = onOpenPage,
                    onFollowToSource = onFollowToSource,
                )
                LibraryControls(
                    query = query,
                    registry = registry,
                    layout = layout,
                    availability = availability,
                    downloads = downloads,
                    onAvailabilityChange = { availability = it },
                    onQueryChange = viewModel::setQuery,
                    onDownloadsChange = { downloads = it },
                    onLayoutChange = viewModel::setLayout,
                    // One action, everything it undoes. The library filter and the download
                    // group are cleared with the rest of them, so there is no state a reader
                    // can be left in without noticing.
                    onClearFilters = {
                        availability = LibraryAvailability.EVERYTHING
                        downloads = DownloadFilter.EITHER
                        viewModel.setQuery(
                            query.withoutFilters().copy(scope = LibraryScope.AllSources),
                        )
                    },
                    viewModel = viewModel,
                )
                cachedAt?.let { CachedNotice(it) }
            }

            // Pull to refresh, and no refresh button. Android was the only platform
            // carrying both, and the gesture is the one Material names for a shelf that
            // re-reads itself.
            PullToRefreshBox(
                isRefreshing = scanState is LibraryScanState.Scanning,
                onRefresh = { viewModel?.rescan() },
                modifier = Modifier.fillMaxSize(),
            ) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    val state = scanState
                    when {
                        shown.isNotEmpty() && viewModel != null -> Shelf(
                            viewModel = viewModel,
                            publications = shown,
                            continueReading = continueReading,
                            groups = groups,
                            query = query,
                            layout = layout,
                            availability = availability,
                            downloads = downloads,
                            selection = selection,
                            onSelectionChange = { selection = it },
                            onOpen = onOpen,
                            onOpenPage = onOpenPage,
                            onAddToShelf = { shelving = it },
                        )

                        // A library that is not empty but looks it. `library-browsing`
                        // forbids showing that silently: say what is narrowing it and
                        // offer one action to undo.
                        publications.isNotEmpty() && viewModel != null ->
                            NarrowedToNothing(
                                query = query,
                                isOnDeviceOnly = availability.isNarrowing &&
                                    visible.isNotEmpty(),
                                // Everything this button claims to undo, the download group
                                // included. One that left a facet set would leave the shelf
                                // as empty as it found it.
                                onClear = {
                                    availability = LibraryAvailability.EVERYTHING
                                    downloads = DownloadFilter.EITHER
                                    viewModel.setQuery(
                                        query.withoutFilters()
                                            .copy(search = "", scope = LibraryScope.AllSources),
                                    )
                                },
                                // Offered only when the axis is what is hiding things.
                                onWiden = if (availability.isNarrowing) {
                                    { availability = LibraryAvailability.EVERYTHING }
                                } else {
                                    null
                                },
                            )

                        state is LibraryScanState.Scanning -> Scanning(state.found)

                        // The first thing a reader ever sees when they own nothing: one
                        // sentence, one action that opens a comic with nothing to configure
                        // first, and one plain secondary behind which the four kinds of
                        // place are named. It had been written, translated and reachable by
                        // nobody — the call here resolved to the superseded overload next
                        // door, which put the four transports on the screen in the order
                        // `sources` forbids and offered no way to open a comic at all.
                        registry.sources.isEmpty() -> EmptyLibrary(
                            onOpenComic = { importFile.launch(arrayOf("*/*")) },
                            onAddFolder = { pickFolder.launch(null) },
                            onAddCatalogue = onAddCatalogue,
                            onAddKavita = onAddKavita,
                            onAddShare = onAddShare,
                        )

                        // Sources are configured and the shelf is still bare. Two ways to
                        // arrive and they are not the same fact, so they do not get the same
                        // sentence — see [LibraryAway]. What stood here was the source list,
                        // which is the plumbing wearing the shelf's clothes: §6.2 of the
                        // direction puts connections in Settings and nowhere else on the
                        // browse path, and task 2.4 of `one-library-three-destinations`
                        // asked for it to go. iOS removed its own.
                        else -> LibraryAway(
                            isEverythingAway = everythingAway(registry),
                            // Both halves, as iOS's `retrySources` does: `sources` already
                            // retries on a backoff while the library is on screen, and this
                            // is the reader asking now. Asking the servers without walking
                            // the folders again would leave a reader whose only library is a
                            // folder pressing a button that cannot change anything.
                            onRetry = {
                                onProbeSources()
                                viewModel?.rescan()
                            },
                            onOpenComic = { importFile.launch(arrayOf("*/*")) },
                        )
                    }
                }
            }
        }
    }

    val shelved = shelving
    if (shelved != null && viewModel != null) {
        AddToShelfSheet(
            viewModel = viewModel,
            publications = listOf(shelved),
            onDismiss = { shelving = null },
            onMark = { changing, isRead -> changing.forEach { onMark(it, isRead) } },
            onRestart = { restarting = shelved },
            onAddToServerList = onAddToServerList,
        )
    }

    // The same sheet, handed the whole selection. `collections-and-reading-lists` asks for a
    // bulk add, and a bulk add is this sheet with more than one thing in it.
    if (isShelvingSelection && viewModel != null) {
        AddToShelfSheet(
            viewModel = viewModel,
            publications = publications.filter { it.id in selection },
            onDismiss = { isShelvingSelection = false },
            onMark = { changing, isRead -> changing.forEach { onMark(it, isRead) } },
            onAddToServerList = onAddToServerList,
            onChange = { undo = it },
        )
    }

    // `reading-progress` requires the clear to be confirmed. Outside the sheet because the
    // sheet dismisses itself on the way here, and destructive because it is: the position
    // is the only copy the app promises never to lose.
    val restart = restarting
    if (restart != null && viewModel != null) {
        AlertDialog(
            onDismissRequest = { restarting = null },
            title = { Text(stringResource(R.string.library_restart_title, restart.displayTitle)) },
            text = { Text(stringResource(R.string.library_restart_body)) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.restart(restart)
                    restarting = null
                }) {
                    Text(
                        text = stringResource(R.string.library_restart_confirm),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { restarting = null }) {
                    Text(stringResource(R.string.shelves_cancel))
                }
            },
        )
    }
}

/**
 * The covers themselves, as a grid or as a list.
 *
 * Its own composable so the screen above reads as the four states it has, rather than as
 * one of them written out at length inside a `when`. The search field and the controls are
 * not here: they belong above the refreshable area, and the reader keeps them while the
 * shelf scrolls.
 */
@Composable
private fun Shelf(
    viewModel: LibraryViewModel,
    publications: List<Publication>,
    continueReading: List<Publication>,
    groups: List<MatchGroup>,
    query: LibraryQuery,
    layout: LibraryLayout,
    availability: LibraryAvailability,
    downloads: DownloadFilter,
    selection: LibrarySelection,
    onSelectionChange: (LibrarySelection) -> Unit,
    /** Opens the book. Reached only from the continue-reading row, which offers a resume. */
    onOpen: (Publication, String) -> Unit,
    /** Opens a publication's page. Reached from every cover, in either layout. */
    onOpenPage: (Publication) -> Unit,
    onAddToShelf: (Publication) -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        val resume: (Publication) -> Unit = { publication ->
            viewModel.location(publication)?.let { onOpen(publication, it) }
        }
        // The one word a section can need that is not already on a file.
        val other = stringResource(R.string.library_section_other)
        // How this shelf divides, or nothing when it is short enough to take in at a glance.
        //
        // Never while a search is running: the results are already grouped by why they
        // matched, and a second set of headings cutting across the first would be two
        // answers to one question. The threshold and every refusal below it belong to
        // [LibrarySections]; this only decides that the question is worth asking.
        val sections = remember(publications, query.sort, groups, other) {
            if (groups.isNotEmpty() || publications.size <= LibrarySections.THRESHOLD) {
                emptyList()
            } else {
                LibrarySections.divide(publications, query.sort, other)
            }
        }
        if (layout == LibraryLayout.GRID) {
            CoverGrid(
                publications = publications,
                viewModel = viewModel,
                // Hidden while a search or filter is running: the row is a shortcut to
                // what you were reading, and showing publications the query excluded
                // reads as a bug. Hidden while picking as well: a cover that opened one
                // mid-selection would throw away everything the reader had chosen.
                continueReading = if (
                    query.isNarrowed ||
                    selection.isActive ||
                    availability.isNarrowing ||
                    downloads.isActive
                ) {
                    emptyList()
                } else {
                    continueReading
                },
                sections = sections,
                onOpen = onOpenPage,
                onResume = resume,
                onAddToShelf = onAddToShelf,
                selection = selection.ids.takeIf { selection.isActive },
                onToggle = { onSelectionChange(selection.toggle(it.id)) },
            )
        } else {
            CoverList(
                publications = publications,
                viewModel = viewModel,
                onOpen = onOpenPage,
                selection = selection.ids.takeIf { selection.isActive },
                onToggle = { onSelectionChange(selection.toggle(it.id)) },
                onAddToShelf = onAddToShelf,
                groups = groups,
            )
        }
    }
}

/**
 * The way across to a server's own search.
 *
 * **`kavita-server` requires the query to go to the server when the search is within a
 * Kavita source, and this is what the old scope selector was missing.** Narrowing the
 * library to a Kavita server and typing filtered the *local index* — what this device
 * happens to hold — and the server's own search, which reaches chapters, people, genres
 * and tags, was never asked.
 *
 * Offered rather than substituted: the local matches are useful and immediate, and a
 * search that silently left the device for the network would take a reader looking for a
 * downloaded chapter somewhere they did not ask to go.
 */
@Composable
private fun KavitaSearchOffer(
    registry: SourceRegistry,
    query: LibraryQuery,
    onSearchOnServer: (Source, String) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val server = registry.sources.firstOrNull {
        it.id == query.scope.sourceId &&
            it.kind == SourceKind.KAVITA_SERVER &&
            query.search.isNotBlank()
    } ?: return

    Text(
        text = stringResource(R.string.library_search_on_server, server.displayName),
        style = MaterialTheme.typography.bodySmall,
        color = palette.accent,
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onSearchOnServer(server, query.search) }
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xs),
    )
}

@Preview(name = "Empty library — dark")
@Composable
private fun LibraryScreenEmptyPreview() {
    StoryArcTheme(useDynamicColor = false) { LibraryScreen() }
}
