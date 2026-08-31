package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.input.clearText
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.foundation.text.input.setTextAndPlaceCursorAtEnd
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AppBarWithSearch
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExpandedDockedSearchBarWithGap
import androidx.compose.material3.ExpandedFullScreenContainedSearchBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.SearchBarScrollBehavior
import androidx.compose.material3.SearchBarValue
import androidx.compose.material3.SegmentedListItem
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberContainedSearchBarState
import androidx.compose.material3.rememberSearchBarWithGapState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.rememberWindowClass
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.MatchKind
import app.storyarc.core.model.Publication
import app.storyarc.core.model.RecentSearches
import app.storyarc.core.model.SearchRoute
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.CertificatePinStore
import app.storyarc.core.persistence.CredentialStore
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

/**
 * Search, wired to the library it is a search of.
 *
 * One composable rather than a dozen lines repeated at each place the shelf puts a field up:
 * the whole question — who is asked, what comes back, what a tap on a row does — is settled
 * here, and the screen above only says *where the bar goes*. That is also what keeps
 * `LibraryScreen` from gaining the fan-out, the stores and the routing on top of everything
 * else it already carries.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LibrarySearchEntry(
    viewModel: LibraryViewModel,
    query: LibraryQuery,
    recents: RecentSearches,
    /**
     * How the app layer reaches a publication's own page.
     *
     * A result the device already holds is a cover like any other, and
     * `publication-detail` puts a page behind a cover chosen "in search results" by name.
     * A result only a server has is not a publication yet, so it is followed to the server
     * instead — see [onFollowToSource].
     */
    onOpenPage: (Publication) -> Unit,
    /** How the app layer reaches a library that is not on this device, carrying the term. */
    onFollowToSource: (Source, String) -> Unit,
    /** What the reader narrowed the question to. Passed straight through to the bar. */
    searchScope: LibraryAvailability = LibraryAvailability.EVERYTHING,
    onSearchScopeChange: (LibraryAvailability) -> Unit = {},
    /** The scaffold's own scroll behaviour. See [LibrarySearchBar]. */
    scrollBehavior: SearchBarScrollBehavior? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val search = remember(scope) { LibrarySearch(scope) }

    // Read-only here: a search reads a secret to ask a question with it and never writes one.
    // Null where the platform keystore refuses to open, which `sources` treats as a library
    // with no secret rather than as a failure — the local half of the search still answers.
    val credentials = remember(context) { CredentialStore.open(context) }
    val pins = remember(context) { CertificatePins(CertificatePinStore.open(context).pins()) }

    val listing by search.listing.collectAsStateWithLifecycle()
    val groups by viewModel.matchGroups.collectAsStateWithLifecycle()
    val registry by viewModel.registry.collectAsStateWithLifecycle()

    // The one place the question is asked. Keyed on the term the model holds rather than on a
    // second piece of state, so a recent search chosen from the list runs exactly as if it
    // had been typed.
    //
    // **Not keyed on the local matches, deliberately.** Keying on them too
    // reads as the more correct thing and is the opposite: the index recomputes when a scan
    // ticks and when progress reloads, and each of those restarted the fan-out — throwing
    // away every remote answer that had already arrived, under a reader who had not touched
    // the keyboard. The local rows are a snapshot taken when the question is asked, which is
    // what iOS does as well.
    //
    // **Keyed on the scope as well**, because the scope decides who is asked and not only which
    // rows survive: `library-browsing` says narrowing to the device "removes that notice,
    // because nothing is then being waited for", and a fan-out already in flight has to be
    // cancelled and re-asked for that to be true. `ask` cancels the previous one on the way in.
    LaunchedEffect(query.search, searchScope) {
        search.ask(query.search, groups, registry, credentials, pins, searchScope)
    }

    LibrarySearchBar(
        query = query.search,
        onQueryChange = { viewModel.setQuery(viewModel.query.value.copy(search = it)) },
        recents = recents,
        onClearRecents = viewModel::clearRecentSearches,
        listing = listing,
        onOpenHeld = { id ->
            viewModel.publications.value.firstOrNull { it.id == id }?.let(onOpenPage)
        },
        // A row a server answered leads to that server, opened on the question rather than at
        // its front door — and never to the publication page, which resolves against the
        // library's own set and would say the publication is gone. The row already names the
        // library; this is where the reader arrives in it.
        onFollow = { route ->
            registry.sources.firstOrNull { it.id.toString() == route.sourceId }?.let { source ->
                onFollowToSource(source, listing.term)
            }
        },
        onRetry = { id -> search.retry(id, registry.sources, credentials, pins) },
        searchScope = searchScope,
        onSearchScopeChange = onSearchScopeChange,
        scrollBehavior = scrollBehavior,
        modifier = modifier,
    )
}

/**
 * The search bar, and what it finds.
 *
 * [AppBarWithSearch] collapsed, then [ExpandedFullScreenContainedSearchBar] on a phone and
 * [ExpandedDockedSearchBarWithGap] where there is room. The contained style is what
 * `MaterialExpressiveTheme` mandates — Material marks the divided style *"Not recommended.
 * Use contained"*. The design direction names the collapsed control `TopSearchBar`, which is
 * what it was called until material3 1.5.0-alpha26 renamed it; same control, same slot.
 *
 * **This comment used to argue that search was a bar rather than a destination**: "Material
 * ranks a search bar above a search destination and permits the destination only for an app
 * whose primary action is searching. StoryArc's is browsing. So the navigation graph has three
 * destinations and no fourth." Material's sentence is quoted correctly and still says that —
 * it is permission conditioned on a judgement — and the judgement changed, for a reason about
 * this app: publications arrive from a device, a folder, an OPDS catalogue, a Kavita server
 * and an SMB share, and no shelf shows all of them at once in a way a reader can scan. Search
 * is the only surface that spans them. See [SearchScreen] and `AppDestination.SEARCH`.
 *
 * The bar itself did not change shape when search became a place; it moved from the library's
 * own top to the search screen's, and gained the state partners, the colours, the scroll
 * behaviour, the two hand-written icons and the chips below.
 *
 * **Two things here are hand-written because there is nothing to call.** Material requires
 * that "the back icon releases focus" and no API supplies it, and Material asks for "an
 * optional clear icon" while `SearchBarDefaults` publishes no clear affordance of any kind.
 * Both verified with `javap` over `material3.aar` at 1.5.0-alpha26.
 *
 * What is *inside* the expanded bar is the part that matters, and it is the same on both
 * platforms: one list, headed by what the match is, each row naming the library that supplied
 * it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LibrarySearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
    recents: RecentSearches,
    onClearRecents: () -> Unit,
    listing: SearchListing,
    onOpenHeld: (String) -> Unit,
    onFollow: (SearchRoute) -> Unit,
    onRetry: (String) -> Unit,
    /**
     * What the reader narrowed the question to.
     *
     * [LibraryAvailability], not a `SearchScope` of its own: it already means exactly this,
     * already names both states for a control, and `narrowedTo` already answers it over a list
     * of publications. Two names for one idea would drift on the day one of them gained a
     * third case. iOS reuses its own equivalent for the same reason.
     */
    searchScope: LibraryAvailability = LibraryAvailability.EVERYTHING,
    onSearchScopeChange: (LibraryAvailability) -> Unit = {},
    /**
     * Material's scroll-away-and-return behaviour, from the `Scaffold` that owns the top bar.
     *
     * Passed in rather than remembered here, because it has to be the **same** behaviour the
     * scaffold hands its content connection — a second one made in this function would track a
     * scroll nothing reports to it, and the bar would never move.
     */
    scrollBehavior: SearchBarScrollBehavior? = null,
    modifier: Modifier = Modifier,
) {
    val windowClass = rememberWindowClass()
    val isDocked = windowClass.showsSidebar

    // **One state per branch, and one shared state cannot be right for both.** Each expanded
    // bar names its required partner in its own KDoc, and `javap` over `material3.aar` shows
    // why: `rememberContainedSearchBarState` and `rememberSearchBarWithGapState` each take
    // their own list of animation specs, and only those carry the content-fade specs their own
    // bar reads. The generic `rememberSearchBarState` this used to call was handed to both, so
    // whichever branch a window landed on animated against specs written for the other.
    //
    // Both are remembered, not one behind an `if`: a branch is a composition-structure change,
    // and a state created inside one is lost the moment a fold or a rotation moves the window
    // across the boundary — mid-search, with the bar open.
    val containedState = rememberContainedSearchBarState()
    val dockedState = rememberSearchBarWithGapState()
    val state = if (isDocked) dockedState else containedState

    val field = rememberTextFieldState(query)
    val scope = rememberCoroutineScope()
    val isExpanded = state.currentValue == SearchBarValue.Expanded

    // One direction only, and deliberately: the field is the reader's, and writing the model
    // back into it mid-word is how a search box eats a keystroke. `drop(1)` skips the value
    // the field was built with, which is already the query.
    LaunchedEffect(field) {
        snapshotFlow { field.text.toString() }.drop(1).collect(onQueryChange)
    }

    // The contained style's own colours, which interpolate **as the bar expands** — that is
    // why the factory takes the state. Without them the bar is drawn with baseline colours and
    // does not move, which reads as a missing animation rather than as wrong colour.
    val searchColors = SearchBarDefaults.containedColors(state)
    val barColors = SearchBarDefaults.appBarWithSearchColors(searchColors)

    val inputField: @Composable () -> Unit = {
        SearchBarDefaults.InputField(
            textFieldState = field,
            searchBarState = state,
            onSearch = { scope.launch { state.animateToCollapsed() } },
            placeholder = { Text(stringResource(R.string.library_search)) },
            // **Hand-written, because no API supplies it.** Material requires that "the back
            // icon releases focus" when the bar is expanded, and `InputField` takes
            // `leadingIcon` as a plain slot with no opinion about what goes in it. Collapsing
            // the bar is what releases the focus; the magnifier is not a control at all when
            // the bar is shut, so it is an `Icon` rather than a dead button.
            leadingIcon = {
                if (isExpanded) {
                    IconButton(onClick = { scope.launch { state.animateToCollapsed() } }) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.library_search_back),
                        )
                    }
                } else {
                    Icon(Icons.Filled.Search, contentDescription = null)
                }
            },
            // Material asks for "an optional clear icon", and `SearchBarDefaults` publishes no
            // clear affordance of any kind — verified with `javap` over the whole class. Drawn
            // only when there is something to clear: a permanent one is a control that does
            // nothing most of the time, and reads as broken the first time it is tried.
            trailingIcon = {
                if (isExpanded && field.text.isNotEmpty()) {
                    IconButton(onClick = { field.clearText() }) {
                        Icon(
                            imageVector = Icons.Filled.Close,
                            contentDescription = stringResource(R.string.library_search_clear),
                        )
                    }
                }
            },
            colors = searchColors.inputFieldColors,
        )
    }

    AppBarWithSearch(
        state = state,
        inputField = inputField,
        modifier = modifier,
        colors = barColors,
        // Material's own scroll-away-and-return, which does not exist unless it is passed:
        // the parameter defaults to none, so a bar that was never handed one simply never
        // moves.
        scrollBehavior = scrollBehavior,
    )

    val results: @Composable () -> Unit = {
        SearchAnswerList(
            listing = listing,
            recents = recents,
            onUseRecent = { term ->
                field.setTextAndPlaceCursorAtEnd(term)
            },
            onClearRecents = onClearRecents,
            onOpenHeld = onOpenHeld,
            onFollow = onFollow,
            onRetry = onRetry,
            scope = searchScope,
            onScopeChange = onSearchScopeChange,
        )
    }

    // **The expanded bar covers the navigation bar by construction**, which is why no hide or
    // show logic is written for it. Material's own navigation-bar page describes exactly this:
    // the search flow "temporarily covering the bottom navigation bar until the search flow is
    // completed". Writing it by hand would duplicate the component and fight predictive back.
    if (isDocked) {
        ExpandedDockedSearchBarWithGap(
            state = dockedState,
            inputField = inputField,
            colors = searchColors,
        ) { results() }
    } else {
        ExpandedFullScreenContainedSearchBar(
            state = containedState,
            inputField = inputField,
            colors = searchColors,
        ) { results() }
    }
}

/**
 * What one search found, wherever it was found.
 *
 * `library-browsing`'s *Mixed local and server search*: results are "merged into one ranked
 * list, each labelled with its source", under headings that say what the match *is*. The label
 * is drawn only where more than one place could have answered, which is
 * [SearchListing.namesOrigin]'s rule. Rows arrive in two waves: the device's own matches are
 * here in the frame the reader typed in, and a server's join when they arrive. No row is ever
 * removed, replaced or reordered against another — and a late row can still push a *later
 * heading* down the screen. Exactly what is and is not promised lives on [SearchListing].
 */
@Composable
private fun SearchAnswerList(
    listing: SearchListing,
    recents: RecentSearches,
    onUseRecent: (String) -> Unit,
    onClearRecents: () -> Unit,
    onOpenHeld: (String) -> Unit,
    onFollow: (SearchRoute) -> Unit,
    onRetry: (String) -> Unit,
    scope: LibraryAvailability,
    onScopeChange: (LibraryAvailability) -> Unit,
) {
    val palette = LocalStoryArcPalette.current

    LazyColumn(modifier = Modifier.fillMaxWidth()) {
        // `library-browsing`: the screen "states what it is searching" and lets a reader narrow
        // it. First, above everything, because it is a fact about every row below it.
        item(key = "scope") { ScopeChips(scope, onScopeChange) }

        // `library-browsing`: "when a reader opens search, recent queries are offered, and
        // can be cleared". Offered instead of results rather than above them — once there is
        // something to read, a list of what was asked before is in the way.
        if (listing.term.isEmpty()) {
            if (recents.terms.isNotEmpty()) {
                item { Heading(stringResource(R.string.library_search_recent)) }
                items(recents.terms) { term ->
                    Text(
                        text = term,
                        style = MaterialTheme.typography.bodyLarge,
                        color = palette.textPrimary,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onUseRecent(term) }
                            .padding(StoryArcSpace.gutter, StoryArcSpace.sm),
                    )
                }
                item {
                    TextButton(
                        onClick = onClearRecents,
                        modifier = Modifier.padding(horizontal = StoryArcSpace.md),
                    ) {
                        Text(stringResource(R.string.library_search_recent_clear))
                    }
                }
            }
            return@LazyColumn
        }

        if (listing.rows.isEmpty() && !listing.isWaiting) {
            // Named, per `library-browsing`: an empty state that does not say what was
            // searched for leaves a reader wondering whether the app heard them.
            item { Quiet(stringResource(R.string.library_empty_search, listing.term)) }
        }

        listing.groups.forEach { group ->
            item(key = "heading:${group.kind}") {
                Heading(stringResource(group.kind.headingRes))
            }
            items(group.rows, key = { it.id }) { found ->
                ResultRow(
                    found = found,
                    namesOrigin = listing.namesOrigin,
                    onOpenHeld = onOpenHeld,
                    onFollow = onFollow,
                    index = group.rows.indexOf(found),
                    count = group.rows.size,
                )
            }
        }

        // Last, under everything, and quiet. Both of these are the app talking about itself,
        // and neither is worth a row's worth of attention while there are results above them.
        if (listing.isWaiting) {
            item(key = "waiting") {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
                    modifier = Modifier.padding(StoryArcSpace.gutter, StoryArcSpace.sm),
                ) {
                    CircularProgressIndicator(modifier = Modifier.size(WAITING_SPINNER_DP.dp))
                    Text(
                        text = stringResource(R.string.search_waiting),
                        style = MaterialTheme.typography.bodySmall,
                        color = palette.textSecondary,
                    )
                }
            }
        }

        // `sources`: an unreachable library "is grey, never red". A sentence at the foot of
        // results the reader can already use, not an alert over the top of them.
        items(listing.silent, key = { "silent:${it.sourceId}" }) { source ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = StoryArcSpace.gutter),
            ) {
                Text(
                    text = stringResource(R.string.search_silent, source.name),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = { onRetry(source.sourceId) }) {
                    Text(stringResource(R.string.search_retry))
                }
            }
        }
    }
}

/**
 * What the search is about to search, and the one narrowing a reader on a train wants.
 *
 * **Filter chips, not a segmented control.** Material retired the segmented button in the
 * Expressive update, and its named replacement is specified for *"two to five toggleable
 * views"* — a fixed, known set. Our sources are an open, growing one: a device, folders, OPDS
 * catalogues, Kavita servers and SMB shares, however many of each a reader adds. Material's own
 * search page lists *"filter chips to narrow down results"*.
 *
 * iOS diverges and uses its segmented scope bar, which is current and idiomatic there. That
 * divergence is deliberate and the change's `design.md` carries it.
 *
 * Two chips rather than one toggle, so the current state is *named* rather than merely set —
 * `library-browsing` asks the screen to state what it is searching, not only to let it be
 * changed.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ScopeChips(scope: LibraryAvailability, onScopeChange: (LibraryAvailability) -> Unit) {
    // **A wrapping row, and the `Row` it replaced is why.** A `Row` measures its children in
    // order and gives the second whatever width the first left, so at the largest text size in
    // a 320 dp window *On this device* was drawn over four lines with a lone "e" on the last
    // one — photographed on an emulator, in `docs/designs/screenshots/before-2026-08-31d/`.
    // Wrapping gives the second chip its own line at its natural width instead. `ListOrderChips`
    // reached the same layout from the same failure, and `design.md` §3 rule 3 makes surviving
    // that text size a requirement.
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        modifier = Modifier
            .fillMaxWidth()
            .padding(StoryArcSpace.gutter, StoryArcSpace.sm),
    ) {
        LibraryAvailability.entries.forEach { option ->
            FilterChip(
                selected = scope == option,
                onClick = { onScopeChange(option) },
                label = { Text(stringResource(option.searchScopeLabel)) },
            )
        }
    }
}

/**
 * What each scope is called on the search screen.
 *
 * The shelf's own two strings, already translated into all four languages — two spellings of
 * "On this device" in one app is how a vocabulary drifts, and `originLabel` a few lines down
 * makes the same point about the same words.
 */
internal val LibraryAvailability.searchScopeLabel: Int
    get() = when (this) {
        LibraryAvailability.EVERYTHING -> R.string.library_scope_all
        LibraryAvailability.ON_THIS_DEVICE -> R.string.source_on_this_device
    }

/**
 * One result.
 *
 * Three shapes, and the difference between them is only what happens on a tap: a book the
 * device holds opens; something a server has is followed to; a person or a tag is a name the
 * server matched and goes nowhere, so it is not drawn as though it might.
 *
 * **A [ListItem], and a [SegmentedListItem] where the group has more than one row.** Material:
 * *"use segmented gaps and filled list items to define a list group"* — dividers are for
 * uncontained lists, and this list sits on the expanded bar's own surface. The container is
 * transparent for the same reason: a filled container here would paint a second surface over
 * the one the bar already draws.
 */
@Composable
private fun ResultRow(
    found: FoundRow,
    namesOrigin: Boolean,
    onOpenHeld: (String) -> Unit,
    onFollow: (SearchRoute) -> Unit,
    /** Where this row sits in its heading's run, and how long that run is. */
    index: Int,
    count: Int,
) {
    val palette = LocalStoryArcPalette.current
    val result = found.result
    val held = result.publicationId
    val route = result.route
    val tap = Modifier.let {
        when {
            held != null -> it.clickable { onOpenHeld(held) }
            route != null -> it.clickable { onFollow(route) }
            else -> it
        }
    }

    val headline: @Composable () -> Unit = {
        Text(
            text = result.title,
            style = MaterialTheme.typography.bodyLarge,
            color = if (result.isOpenable) palette.textPrimary else palette.textSecondary,
        )
    }
    val supporting: (@Composable () -> Unit)? = supportingLines(found, namesOrigin, palette)
    val colors = ListItemDefaults.colors(containerColor = Color.Transparent)

    if (count > 1) {
        // `ListItemDefaults.segmentedShapes(index, count)` is what rounds the first and last
        // row of a run and squares the ones between, which is how Material draws a group
        // without a rule through it.
        SegmentedListItem(
            shapes = ListItemDefaults.segmentedShapes(index, count),
            supportingContent = supporting,
            colors = colors,
            modifier = Modifier.fillMaxWidth().then(tap),
            content = headline,
        )
    } else {
        // A run of one is not a group, and a segmented shape over a single row draws a
        // container around nothing.
        ListItem(
            supportingContent = supporting,
            colors = colors,
            modifier = Modifier.fillMaxWidth().then(tap),
            content = headline,
        )
    }
}

/**
 * The two lines under a result's title, or neither.
 *
 * Its own function so [ResultRow] can hand the same content to both list-item shapes without
 * writing it twice — which is how one of the two would come to be missing a line.
 */
@Composable
private fun supportingLines(
    found: FoundRow,
    namesOrigin: Boolean,
    palette: app.storyarc.core.designsystem.theme.StoryArcPalette,
): (@Composable () -> Unit)? {
    val detail = found.result.detail?.takeIf { it.isNotEmpty() }
    val origin = if (namesOrigin) originLabel(found.origin) else null
    if (detail == null && origin == null) return null

    return {
        Column {
            // The series or the author — what tells a reader which "Volume 1" this is.
            detail?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }
            // The label the scenario asks for, under the row rather than beside it: a
            // library's name is as long as the reader made it, and a trailing label would
            // take its width from the title at the largest text size.
            origin?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textTertiary,
                )
            }
        }
    }
}

/**
 * Which library a row came from, in the reader's own words.
 *
 * The same two strings the shelf and the publication page use — two spellings of "On this
 * device" in one app is how a vocabulary drifts. Nothing else about the library reaches the
 * row: no protocol, no address, no product, no path.
 */
@Composable
private fun originLabel(origin: SearchOrigin): String = when (origin) {
    is SearchOrigin.Library -> stringResource(R.string.library_cell_source, origin.name)
    SearchOrigin.ThisDevice -> stringResource(R.string.source_on_this_device)
}

@Composable
private fun Heading(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleSmall,
        color = LocalStoryArcPalette.current.textSecondary,
        modifier = Modifier.padding(
            start = StoryArcSpace.gutter,
            end = StoryArcSpace.gutter,
            top = StoryArcSpace.md,
            bottom = StoryArcSpace.xs,
        ),
    )
}

@Composable
private fun Quiet(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = LocalStoryArcPalette.current.textSecondary,
        modifier = Modifier.padding(StoryArcSpace.gutter, StoryArcSpace.sm),
    )
}

/**
 * How a match kind is named on screen.
 *
 * The kinds live in `:core:model` and carry no resources: the domain has no business holding
 * UI copy. The same four strings the shelf's own group headings use, so a heading reads the
 * same whether the reader got there by searching or by scrolling.
 */
private val MatchKind.headingRes: Int
    get() = when (this) {
        MatchKind.SERIES -> R.string.library_match_series
        MatchKind.PUBLICATION -> R.string.library_match_publication
        MatchKind.PERSON -> R.string.library_match_person
        MatchKind.TAG -> R.string.library_match_tag
    }

private const val WAITING_SPINNER_DP = 16
