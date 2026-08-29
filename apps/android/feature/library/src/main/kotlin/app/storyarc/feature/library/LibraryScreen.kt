package app.storyarc.feature.library

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.LibraryLayout
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.LibrarySort
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.ReadState
import app.storyarc.core.model.RecentSearches
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import kotlinx.coroutines.flow.MutableStateFlow

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
    viewModel: LibraryViewModel? = null,
    /**
     * How the app layer reaches the reader. The library knows which publication
     * was chosen and where it lives; it does not know what a reader is.
     */
    onOpen: (Publication, String) -> Unit = { _, _ -> },
    /**
     * How the app layer reaches Settings.
     *
     * The library does not know what a settings screen is, for the same reason it does
     * not know what a reader is: a feature module never depends on another feature
     * module. It reports that the reader asked.
     */
    onOpenSettings: () -> Unit = {},
    /**
     * How the app layer reaches a catalogue's pages. Same reasoning as `onOpen`: the
     * library knows which catalogue was chosen and does not know what a browser is.
     */
    onBrowse: (Source) -> Unit = {},
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

    /** The publication whose add-to-shelf sheet is open, if any. */
    var shelving by remember { mutableStateOf<Publication?>(null) }
    var restarting by remember { mutableStateOf<Publication?>(null) }

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

    LaunchedEffect(viewModel) {
        viewModel?.restoreFolders()
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
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { viewModel?.refreshProgress() }
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

    Scaffold(
        modifier = modifier,
        containerColor = palette.surfaceCanvas,
        snackbarHost = { SnackbarHost(snackbars) },
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.library_title)) },
                actions = {
                    if (viewModel != null && publications.isNotEmpty()) {
                        LayoutToggle(layout, viewModel::setLayout)
                        SortMenu(query, viewModel::setQuery)
                        FilterMenu(query, viewModel)
                    }
                    if (viewModel != null) {
                        // A menu rather than a second button. There are two ways to add a
                        // source now and there will be four; a toolbar with one button per
                        // kind would crowd out the controls a reader uses every day.
                        AddSourceMenu(
                            onAddFolder = { pickFolder.launch(null) },
                            onAddCatalogue = onAddCatalogue,
                            onAddKavita = onAddKavita,
                            onAddShare = onAddShare,
                        )
                        IconButton(onClick = { viewModel.rescan() }) {
                            Icon(
                                imageVector = Icons.Filled.Refresh,
                                contentDescription = stringResource(
                                    R.string.library_scan_folder,
                                ),
                                tint = palette.accent,
                            )
                        }
                    }
                    // Last, and always present. A reader with an empty library still
                    // needs to reach About, and `settings-and-about` puts the licences
                    // there.
                    IconButton(onClick = onOpenShelves) {
                        Icon(
                            imageVector = Icons.Filled.Inventory2,
                            contentDescription = stringResource(R.string.shelves_title),
                            tint = palette.accent,
                        )
                    }
                    IconButton(onClick = onOpenSettings) {
                        Icon(
                            imageVector = Icons.Filled.Settings,
                            contentDescription = stringResource(R.string.library_settings),
                            tint = palette.accent,
                        )
                    }
                },
            )
        },
        bottomBar = {
            val state = scanState
            if (unavailable.isNotEmpty()) {
                UnavailableFolders(
                    names = unavailable,
                    onRepick = { pickFolder.launch(null) },
                )
            } else if (state is LibraryScanState.Finished && state.skipped > 0) {
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
        Column(modifier = Modifier.fillMaxSize().padding(insets)) {
            // Above the library rather than inside it. A catalogue is not a shelf of local
            // publications -- nothing in it is on the device yet -- and mixing the two
            // would make "what can I read on the train" unanswerable.
            // Catalogues and Kavita servers together: both are places to browse rather than
            // shelves of local publications, and a reader with one of each should not have to
            // learn two ways in.
            // Catalogues, servers and shares together: all three are places to browse
            // rather than shelves of local publications, and a reader with one of each
            // should not have to learn three ways in.
            val catalogues = registry.sources.filter {
                it.kind == SourceKind.OPDS_CATALOG ||
                    it.kind == SourceKind.KAVITA_SERVER ||
                    it.kind == SourceKind.NETWORK_SHARE
            }
            if (catalogues.isNotEmpty()) {
                CatalogueStrip(sources = catalogues, onOpen = onBrowse)
            }

        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            val state = scanState
            when {
                visible.isNotEmpty() && viewModel != null ->
                    Column(modifier = Modifier.fillMaxSize()) {
                        SearchField(
                            value = query.search,
                            recents = recentSearches,
                            onChange = { viewModel.setQuery(query.copy(search = it)) },
                            onClearRecents = viewModel::clearRecentSearches,
                        )
                        cachedAt?.let { CachedNotice(it) }
                        val open: (Publication) -> Unit = { publication ->
                            viewModel.location(publication)?.let { onOpen(publication, it) }
                        }
                        val addToShelf: (Publication) -> Unit = { shelving = it }
                        if (layout == LibraryLayout.GRID) {
                            CoverGrid(
                                publications = visible,
                                viewModel = viewModel,
                                // Hidden while a search or filter is running: the
                                // row is a shortcut to what you were reading, and
                                // showing publications the query excluded reads as
                                // a bug.
                                continueReading =
                                    if (query.isNarrowed) emptyList() else continueReading,
                                onOpen = open,
                                onAddToShelf = addToShelf,
                            )
                        } else {
                            CoverList(
                                publications = visible,
                                viewModel = viewModel,
                                onOpen = open,
                            )
                        }
                    }

                // A library that is not empty but looks it. `library-browsing`
                // forbids showing that silently: say what is narrowing it and
                // offer one action to undo.
                publications.isNotEmpty() && viewModel != null ->
                    Column(modifier = Modifier.fillMaxSize()) {
                        SearchField(
                            value = query.search,
                            recents = recentSearches,
                            onChange = { viewModel.setQuery(query.copy(search = it)) },
                            onClearRecents = viewModel::clearRecentSearches,
                        )
                        cachedAt?.let { CachedNotice(it) }
                        NarrowedToNothing(
                            query = query,
                            onClear = {
                                viewModel.clearFilters()
                                viewModel.setQuery(viewModel.query.value.copy(search = ""))
                            },
                        )
                    }

                state is LibraryScanState.Scanning -> Scanning(state.found)
                registry.sources.isEmpty() -> EmptyLibrary(onScan = { pickFolder.launch(null) })
                else -> SourceList(
                    sources = registry.sources,
                    itemCount = { viewModel?.itemCount(it.id) ?: 0 },
                    onRemove = viewModel?.let { model -> { model.removeSource(it) } },
                )
            }
        }
        }
    }

    val shelved = shelving
    if (shelved != null && viewModel != null) {
        AddToShelfSheet(
            viewModel = viewModel,
            publication = shelved,
            onDismiss = { shelving = null },
            onMark = { isRead -> onMark(shelved, isRead) },
            onRestart = { restarting = shelved },
            onAddToServerList = onAddToServerList?.let { add -> { list -> add(shelved, list) } },
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
 * `library-browsing`: results update as the user types, debounced, with no submit
 * action. Arranging is a sort of what is already in memory, so a keystroke costs
 * one pass rather than a request.
 */
@Composable
private fun SearchField(
    value: String,
    recents: RecentSearches,
    onChange: (String) -> Unit,
    onClearRecents: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var isFocused by remember { mutableStateOf(false) }

    Column(modifier = modifier) {
        OutlinedTextField(
            value = value,
            onValueChange = onChange,
            singleLine = true,
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            placeholder = { Text(stringResource(R.string.library_search)) },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm)
                .onFocusChanged { isFocused = it.isFocused },
        )
        // Offered only while nothing has been typed — once there is a term, the
        // results below are the better answer, and a list of old searches on top of
        // them would hide what was just found.
        if (isFocused && value.isBlank() && !recents.isEmpty) {
            RecentSearchList(recents.terms, onUse = onChange, onClear = onClearRecents)
        }
    }
}

/**
 * What the reader searched for lately, under an open search field.
 *
 * `library-browsing`: "when a user opens search, recent queries are offered, and
 * can be cleared". Choosing one puts the term in the field, which runs the search:
 * a recent query is a shortcut to the search, not to whatever it found last time.
 */
@Composable
private fun RecentSearchList(
    terms: List<String>,
    onUse: (String) -> Unit,
    onClear: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier.padding(horizontal = StoryArcSpace.gutter)) {
        Text(
            text = stringResource(R.string.library_search_recent),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textTertiary,
            modifier = Modifier.padding(vertical = StoryArcSpace.xs),
        )
        terms.forEach { term ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onUse(term) }
                    // Material's 48 dp touch-target floor, per `native-experience`.
                    .heightIn(min = StoryArcSpace.xxl + StoryArcSpace.lg)
                    .padding(vertical = StoryArcSpace.xs),
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Filled.History,
                    contentDescription = null,
                    tint = palette.textTertiary,
                )
                Text(
                    text = term,
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                )
            }
        }
        TextButton(onClick = onClear) {
            Text(stringResource(R.string.library_search_recent_clear))
        }
    }
}

/**
 * Grid or list.
 *
 * One button that shows the layout it would switch *to*, rather than a segmented
 * control that spends permanent space on a binary choice.
 */
@Composable
private fun LayoutToggle(layout: LibraryLayout, onChange: (LibraryLayout) -> Unit) {
    val palette = LocalStoryArcPalette.current
    val isGrid = layout == LibraryLayout.GRID
    IconButton(
        onClick = { onChange(if (isGrid) LibraryLayout.LIST else LibraryLayout.GRID) },
    ) {
        Icon(
            imageVector = if (isGrid) Icons.AutoMirrored.Filled.List else Icons.Filled.GridView,
            contentDescription = stringResource(
                if (isGrid) R.string.library_layout_list else R.string.library_layout_grid,
            ),
            tint = palette.accent,
        )
    }
}

/** How the library is ordered. */
@Composable
private fun SortMenu(query: LibraryQuery, onChange: (LibraryQuery) -> Unit) {
    val palette = LocalStoryArcPalette.current
    var open by remember { mutableStateOf(false) }

    IconButton(onClick = { open = true }) {
        Icon(
            imageVector = Icons.AutoMirrored.Filled.Sort,
            contentDescription = stringResource(R.string.library_sort),
            tint = palette.accent,
        )
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        LibrarySort.entries.forEach { sort ->
            DropdownMenuItem(
                text = { Text(stringResource(sort.labelRes)) },
                leadingIcon = { RadioButton(selected = query.sort == sort, onClick = null) },
                onClick = { onChange(query.copy(sort = sort)) },
            )
        }
        HorizontalDivider()
        listOf(true to R.string.library_sort_ascending, false to R.string.library_sort_descending)
            .forEach { (ascending, label) ->
                DropdownMenuItem(
                    text = { Text(stringResource(label)) },
                    leadingIcon = {
                        RadioButton(selected = query.ascending == ascending, onClick = null)
                    },
                    onClick = { onChange(query.copy(ascending = ascending)) },
                )
            }
    }
}

/**
 * What the library is narrowed to.
 *
 * `library-browsing`: filters combine with AND, the active count is visible on the
 * control, and one action clears them all.
 */
@Composable
private fun FilterMenu(query: LibraryQuery, viewModel: LibraryViewModel) {
    val palette = LocalStoryArcPalette.current
    var open by remember { mutableStateOf(false) }

    IconButton(onClick = { open = true }) {
        Icon(
            imageVector = Icons.Filled.FilterList,
            contentDescription = if (query.hasFilters) {
                // A plural, not a format. "1 filters active" is wrong in every
                // language, and the count reaches 1 whenever a reader sets one filter.
                pluralStringResource(
                    R.plurals.library_filter_active,
                    query.activeFilterCount,
                    query.activeFilterCount,
                )
            } else {
                stringResource(R.string.library_filter)
            },
            // Colour is never the only signal: the count is in the description.
            tint = if (query.hasFilters) palette.accent else palette.textSecondary,
        )
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        MenuHeading(stringResource(R.string.library_filter_read_state))
        ReadState.entries.forEach { state ->
            CheckedItem(stringResource(state.labelRes), state in query.readStates) {
                onChangeSet(query.readStates, state).let {
                    viewModel.setQuery(query.copy(readStates = it))
                }
            }
        }
        MenuHeading(stringResource(R.string.library_filter_format))
        viewModel.availableFormats().forEach { format ->
            CheckedItem(format.displayName, format in query.formats) {
                onChangeSet(query.formats, format).let {
                    viewModel.setQuery(query.copy(formats = it))
                }
            }
        }
        if (query.hasFilters) {
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text(stringResource(R.string.library_filter_clear)) },
                onClick = {
                    viewModel.clearFilters()
                    open = false
                },
            )
        }
    }
}

private fun <T> onChangeSet(current: Set<T>, value: T): Set<T> =
    if (value in current) current - value else current + value

@Composable
private fun MenuHeading(text: String) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge,
        color = palette.textTertiary,
        modifier = Modifier.padding(horizontal = StoryArcSpace.md, vertical = StoryArcSpace.xs),
    )
}

@Composable
private fun CheckedItem(label: String, checked: Boolean, onToggle: () -> Unit) {
    DropdownMenuItem(
        text = { Text(label) },
        leadingIcon = { Checkbox(checked = checked, onCheckedChange = null) },
        onClick = onToggle,
    )
}

/** A library that has publications and is showing none of them. */
@Composable
private fun NarrowedToNothing(
    query: LibraryQuery,
    onClear: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val term = query.search.trim()

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(StoryArcSpace.gutter),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md, Alignment.CenterVertically),
    ) {
        Text(
            // Names what was searched, which is what makes the state actionable
            // rather than a shrug.
            text = if (term.isEmpty()) {
                stringResource(R.string.library_empty_filtered)
            } else {
                stringResource(R.string.library_empty_search, term)
            },
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
            textAlign = TextAlign.Center,
        )
        TextButton(onClick = onClear) { Text(stringResource(R.string.library_filter_clear)) }
    }
}

/**
 * How the browsing enums are named on screen.
 *
 * The enums live in `:core:model` and carry no resources: the domain has no
 * business holding UI copy. Naming them is presentation, so it lives here.
 */
private val LibrarySort.labelRes: Int
    get() = when (this) {
        LibrarySort.TITLE -> R.string.library_sort_title
        LibrarySort.SERIES -> R.string.library_sort_series
        LibrarySort.LAST_READ -> R.string.library_sort_last_read
        LibrarySort.PROGRESS -> R.string.library_sort_progress
        LibrarySort.YEAR -> R.string.library_sort_year
        LibrarySort.DATE_ADDED -> R.string.library_sort_date_added
        LibrarySort.FILE_SIZE -> R.string.library_sort_file_size
    }

private val ReadState.labelRes: Int
    get() = when (this) {
        ReadState.UNREAD -> R.string.library_read_state_unread
        ReadState.IN_PROGRESS -> R.string.library_read_state_in_progress
        ReadState.FINISHED -> R.string.library_read_state_finished
    }

/**
 * A folder that was remembered and can no longer be read.
 *
 * `local-library`: name the folder and offer one action to pick it again. Never a
 * silent disappearance — a library that quietly loses half its rows looks broken
 * rather than disconnected.
 */
@Composable
private fun UnavailableFolders(
    names: List<String>,
    onRepick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(StoryArcSpace.md),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.library_folder_unavailable, names.joinToString(", ")),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
            modifier = Modifier.weight(1f),
        )
        Button(onClick = onRepick) { Text(stringResource(R.string.library_repick_folder)) }
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
private fun SourceList(
    sources: List<Source>,
    modifier: Modifier = Modifier,
    itemCount: (Source) -> Int = { 0 },
    onRemove: ((Source) -> Unit)? = null,
) {
    val palette = LocalStoryArcPalette.current
    var removing by remember { mutableStateOf<Source?>(null) }

    removing?.let { source ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text(stringResource(R.string.source_remove_title, source.displayName)) },
            // `sources` asks the app to state "how many downloaded files and how much disk
            // space will be freed before asking for confirmation". For a folder the honest
            // answer is none and nothing, and saying so is the whole point: a reader must
            // not have to guess whether this deletes their comics.
            text = {
                Text(
                    pluralStringResource(
                        R.plurals.source_remove_body,
                        itemCount(source),
                        itemCount(source),
                    ),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    onRemove?.invoke(source)
                    removing = null
                }) {
                    Text(
                        text = stringResource(R.string.source_remove),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { removing = null }) {
                    Text(stringResource(R.string.library_cancel))
                }
            },
        )
    }

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

                    if (onRemove != null) {
                        IconButton(onClick = { removing = source }) {
                            Icon(
                                imageVector = Icons.Filled.Delete,
                                contentDescription = stringResource(
                                    R.string.source_remove_action,
                                    source.displayName,
                                ),
                                tint = palette.textSecondary,
                            )
                        }
                    }
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
