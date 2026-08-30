package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.foundation.text.input.setTextAndPlaceCursorAtEnd
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AppBarWithSearch
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExpandedDockedSearchBarWithGap
import androidx.compose.material3.ExpandedFullScreenContainedSearchBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSearchBarState
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
import app.storyarc.core.model.SearchAnswers
import app.storyarc.core.model.SearchResult
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
@Composable
internal fun LibrarySearchEntry(
    viewModel: LibraryViewModel,
    query: LibraryQuery,
    recents: RecentSearches,
    onOpen: (Publication, String) -> Unit,
    /** How the app layer reaches a library that is not on this device, carrying the term. */
    onFollowToSource: (Source, String) -> Unit,
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

    val answers by search.answers.collectAsStateWithLifecycle()
    val groups by viewModel.matchGroups.collectAsStateWithLifecycle()
    val registry by viewModel.registry.collectAsStateWithLifecycle()

    // The one place the question is asked. Keyed on the term the model holds rather than on a
    // second piece of state, so a recent search chosen from the list runs exactly as if it
    // had been typed.
    LaunchedEffect(query.search, groups, registry) {
        search.ask(query.search, groups, registry.sources, credentials, pins)
    }

    LibrarySearchBar(
        query = query.search,
        onQueryChange = { viewModel.setQuery(viewModel.query.value.copy(search = it)) },
        recents = recents,
        onClearRecents = viewModel::clearRecentSearches,
        answers = answers,
        onOpenHeld = { id ->
            viewModel.publications.value.firstOrNull { it.id == id }?.let { publication ->
                viewModel.location(publication)?.let { onOpen(publication, it) }
            }
        },
        // A row a server answered leads to that server, opened on the question rather than at
        // its front door. The reader is not told which server it was until they are standing
        // in it, which is the difference between routing a tap and labelling a result.
        onFollow = { route ->
            registry.sources.firstOrNull { it.id.toString() == route.sourceId }?.let { source ->
                onFollowToSource(source, answers.term)
            }
        },
        onRetry = { id -> search.retry(id, registry.sources, credentials, pins) },
        modifier = modifier,
    )
}

/**
 * The one way into search on Android, and what it finds.
 *
 * **The divergence from iOS is deliberate and the design direction states it.** iOS gives
 * search a `Tab(role: .search)`; Material ranks a search *bar* above a search *destination*
 * and permits the destination only for an app whose primary action is searching. StoryArc's
 * is browsing. So the navigation graph has three destinations and no fourth, and search is a
 * bar that takes over the screen when it is tapped: [AppBarWithSearch] collapsed, then
 * [ExpandedFullScreenContainedSearchBar] on a phone and [ExpandedDockedSearchBarWithGap]
 * where there is room. The design direction names the collapsed control `TopSearchBar`,
 * which is what it was called until material3 1.5.0-alpha26 renamed it and deprecated the
 * old spelling; same control, same slot.
 *
 * Both platforms are being asked for the same behaviour — search is one tap away and takes
 * over the screen — and each says it in its own words.
 *
 * What is *inside* the expanded bar is the part that matters, and it is the same on both:
 * one list, headed by what the match is, with nothing on it naming the library that answered.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun LibrarySearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
    recents: RecentSearches,
    onClearRecents: () -> Unit,
    answers: SearchAnswers,
    onOpenHeld: (String) -> Unit,
    onFollow: (SearchRoute) -> Unit,
    onRetry: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val state = rememberSearchBarState()
    val field = rememberTextFieldState(query)
    val scope = rememberCoroutineScope()
    val windowClass = rememberWindowClass()

    // One direction only, and deliberately: the field is the reader's, and writing the model
    // back into it mid-word is how a search box eats a keystroke. `drop(1)` skips the value
    // the field was built with, which is already the query.
    LaunchedEffect(field) {
        snapshotFlow { field.text.toString() }.drop(1).collect(onQueryChange)
    }

    val inputField: @Composable () -> Unit = {
        SearchBarDefaults.InputField(
            textFieldState = field,
            searchBarState = state,
            onSearch = { scope.launch { state.animateToCollapsed() } },
            placeholder = { Text(stringResource(R.string.library_search)) },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
        )
    }

    AppBarWithSearch(state = state, inputField = inputField, modifier = modifier)

    val results: @Composable () -> Unit = {
        SearchAnswerList(
            answers = answers,
            recents = recents,
            onUseRecent = { term ->
                field.setTextAndPlaceCursorAtEnd(term)
            },
            onClearRecents = onClearRecents,
            onOpenHeld = onOpenHeld,
            onFollow = onFollow,
            onRetry = onRetry,
        )
    }

    if (windowClass.showsSidebar) {
        ExpandedDockedSearchBarWithGap(state = state, inputField = inputField) { results() }
    } else {
        ExpandedFullScreenContainedSearchBar(state = state, inputField = inputField) {
            results()
        }
    }
}

/**
 * What one search found, wherever it was found.
 *
 * `library-browsing`: results are grouped "by what the match is rather than by which source
 * answered", and "no result is labelled with the source that supplied it". Rows arrive in two
 * waves and the list does not notice the difference — the device's own matches are here in
 * the frame the reader typed in, and a server's join underneath when they arrive. Nothing
 * above them moves; that promise lives in `SearchAnswers` and is asserted there.
 */
@Composable
private fun SearchAnswerList(
    answers: SearchAnswers,
    recents: RecentSearches,
    onUseRecent: (String) -> Unit,
    onClearRecents: () -> Unit,
    onOpenHeld: (String) -> Unit,
    onFollow: (SearchRoute) -> Unit,
    onRetry: (String) -> Unit,
) {
    val palette = LocalStoryArcPalette.current

    LazyColumn(modifier = Modifier.fillMaxWidth()) {
        // `library-browsing`: "when a reader opens search, recent queries are offered, and
        // can be cleared". Offered instead of results rather than above them — once there is
        // something to read, a list of what was asked before is in the way.
        if (answers.term.isEmpty()) {
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

        if (answers.results.isEmpty() && !answers.isWaiting) {
            // Named, per `library-browsing`: an empty state that does not say what was
            // searched for leaves a reader wondering whether the app heard them.
            item { Quiet(stringResource(R.string.library_empty_search, answers.term)) }
        }

        answers.groups.forEach { group ->
            item(key = "heading:${group.kind}") {
                Heading(stringResource(group.kind.headingRes))
            }
            items(group.results, key = { it.id }) { result ->
                ResultRow(result, onOpenHeld, onFollow)
            }
        }

        // Last, under everything, and quiet. Both of these are the app talking about itself,
        // and neither is worth a row's worth of attention while there are results above them.
        if (answers.isWaiting) {
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
        items(answers.silent, key = { "silent:${it.sourceId}" }) { source ->
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
 * One result.
 *
 * Three shapes, and the difference between them is only what happens on a tap: a book the
 * device holds opens; something a server has is followed to; a person or a tag is a name the
 * server matched and goes nowhere, so it is not drawn as though it might.
 */
@Composable
private fun ResultRow(
    result: SearchResult,
    onOpenHeld: (String) -> Unit,
    onFollow: (SearchRoute) -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val held = result.publicationId
    val route = result.route
    val tap = Modifier.let {
        when {
            held != null -> it.clickable { onOpenHeld(held) }
            route != null -> it.clickable { onFollow(route) }
            else -> it
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .then(tap)
            .padding(StoryArcSpace.gutter, StoryArcSpace.sm),
    ) {
        Text(
            text = result.title,
            style = MaterialTheme.typography.bodyLarge,
            color = if (result.isOpenable) palette.textPrimary else palette.textSecondary,
        )
        result.detail?.takeIf { it.isNotEmpty() }?.let { detail ->
            // The series or the author — what tells a reader which "Volume 1" this is. Never
            // the library it came from.
            Text(
                text = detail,
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
    }
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
