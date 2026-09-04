package app.storyarc.feature.library

import android.graphics.Bitmap
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication

/**
 * The search page with nothing typed into it yet.
 *
 * `navigation-shell`'s *What search opens onto*: publications the reader already has — one in
 * progress, one never opened, one next in a series they have read. [SearchSuggestions] is the
 * arithmetic; this is the screen.
 *
 * **What was here before was nothing at all**, and the source said so: section 1 moved search
 * onto a page and section 2 built the bar on it, and the page's own body was left named as
 * unfinished. A search page that offers nothing before a letter is typed is the thing the
 * proposal calls out by name — "ours says nothing".
 *
 * **The covers are Home's own cells, not new ones.** [HomeShelfCell] already dims a
 * publication that cannot be opened right now, already truncates a long title at two lines,
 * and already reflows with the reader's text size. A second cell drawn here would be the same
 * book looking like two different books one destination apart.
 *
 * **Where recent searches are, and why they are not here.** They are in the expanded bar,
 * which is where Android's search is *activated* in Material's own vocabulary and where a
 * reader who has pressed to type is looking — with the clear affordance beside them. iOS puts
 * them on the page because its field has no expanded state of its own to put them in. Both
 * platforms satisfy the same two clauses; neither draws the other's answer.
 */
@Composable
internal fun SearchAtRest(
    suggestions: SearchSuggestions,
    /** What the search is narrowed to, shared with the chips inside the expanded bar. */
    scope: LibraryAvailability,
    onScopeChange: (LibraryAvailability) -> Unit,
    cover: suspend (Publication, Int) -> Bitmap?,
    /** A suggestion is a cover like any other, so it leads to the publication's own page. */
    onOpenPage: (Publication) -> Unit,
    /** Copies one file in and opens it. Configures nothing. */
    onOpenComic: () -> Unit,
    onAddFolder: () -> Unit,
    /** The three the app layer owns, because each opens a sheet only it can put up. */
    onAddCatalogue: () -> Unit,
    onAddKavita: () -> Unit,
    onAddShare: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (suggestions.isEmpty) {
        SearchNothingToSuggest(
            scope = scope,
            onScopeChange = onScopeChange,
            onOpenComic = onOpenComic,
            onAddFolder = onAddFolder,
            onAddCatalogue = onAddCatalogue,
            onAddKavita = onAddKavita,
            onAddShare = onAddShare,
            modifier = modifier,
        )
        return
    }

    val width = homeShelfCoverWidth(homeWindowWidthDp(), LocalDensity.current.fontScale)

    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(bottom = StoryArcSpace.xl),
    ) {
        // **What this search is about to search, said before it is run.** `library-browsing`
        // asks the screen to state "whether it is searching everything or only what is on the
        // device" *when the search screen is open* — not only once the bar has been expanded.
        // The chips inside the expanded bar cannot satisfy that clause on their own: a reader
        // who has not pressed to type has never seen them.
        //
        // The same [ScopeChips] over the same value, so the two can never disagree — and the
        // reader sees one of them at a time, because expanding the bar covers this screen.
        // First, above everything, because it is a fact about every row below it.
        item(key = "scope") { ScopeChips(scope, onScopeChange) }

        // Each section is drawn only when it has something in it. `navigation-shell` asks the
        // screen to say so "in one sentence rather than drawing empty headings", and a heading
        // over nothing is the same mistake in miniature.
        shelf("in-progress", R.string.search_suggestions_in_progress, suggestions.inProgress, width, cover, onOpenPage)
        shelf("next", R.string.search_suggestions_next_in_series, suggestions.nextInSeries, width, cover, onOpenPage)
        shelf("never", R.string.search_suggestions_never_opened, suggestions.neverOpened, width, cover, onOpenPage)
    }
}

/** One suggestion shelf, or nothing at all. */
private fun LazyListScope.shelf(
    key: String,
    heading: Int,
    entries: List<HomeEntry>,
    width: Dp,
    cover: suspend (Publication, Int) -> Bitmap?,
    onOpenPage: (Publication) -> Unit,
) {
    if (entries.isEmpty()) return
    item(key = "heading:$key") { SearchSectionHeading(heading) }
    item(key = "run:$key") {
        LazyRow(
            contentPadding = PaddingValues(horizontal = StoryArcSpace.gutter),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.coverGap),
            modifier = Modifier.fillMaxWidth(),
        ) {
            items(entries, key = { it.id }) { entry ->
                // `homeRemainingText` answers *how much is left*, and it used to answer
                // "part-read" for a publication that declared no page count — true of
                // everything Home drew it for and false of two of the three sections here,
                // so every card under *You have never opened these* read "…. Part-read".
                // The guard that stood here has moved inside: the entry's own read state
                // decides, which is one rule instead of two, and it is also right for a
                // finished book, which this one was not.
                val label = homeRemainingText(entry)
                HomeShelfCell(
                    entry = entry,
                    cover = cover,
                    width = width,
                    modifier = Modifier
                        .clickable { onOpenPage(entry.publication) }
                        .homeCardSemantics(entry, label),
                )
            }
        }
    }
}

/**
 * A section heading that leads nowhere.
 *
 * Home's [HomeHeading] carries an arrow because every one of its shelves is a window onto an
 * exhaustive list. None of these three is: *next in a series you have read* is not a shelf
 * the library can be filtered down to, and an arrow that led to the whole library would be
 * answering a question the reader did not ask. So the same weight, and no affordance.
 */
@Composable
private fun SearchSectionHeading(text: Int) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = stringResource(text),
        style = MaterialTheme.typography.titleLarge,
        color = palette.textPrimary,
        modifier = Modifier.padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
    )
}

/**
 * The search page when the library has nothing to suggest from.
 *
 * `navigation-shell`'s *Nothing to suggest*: "the screen says so in one sentence rather than
 * drawing empty headings", and "it offers the same way of adding a source that the library's
 * own empty state offers".
 *
 * The second half is taken literally: all five of the library's ways in, in the order and with
 * the words `EmptyLibrary` uses one destination away. Open a comic is the primary action
 * because `sources` says it "opens a comic from the device with nothing to configure first";
 * the other four sit behind one labelled secondary button, which is where `EmptyLibrary` puts
 * them and for the reason it gives — on an empty screen a reader has nothing to compare a lone
 * plus glyph against.
 *
 * **Two of the five used to be missing**, and the source said the other three were "absent
 * rather than drawn dead" because `SearchScreen` could not reach the sheets the app layer owns.
 * That was true of the module and never true of the app: `SearchDestination` already had the
 * host that puts those sheets up, eight lines from where `LibraryDestination` passes the same
 * three. So a reader who arrived here with an empty library could add a folder and a file and
 * had no way at all to reach a catalogue, a Kavita server or a share — which is the whole point
 * of the requirement, since a reader with no books is exactly the reader who needs a server.
 *
 * The menu is composed here rather than shared with `EmptyLibrary`'s, whose own is private to
 * `LibraryStates.kt`. The pair is held together by [SearchAtRestTest], which reads all five
 * labels out of the same resources — the failure mode iOS's `AddSourceMenu` comment names, one
 * of the two menus ending up a row short, is what that test exists to catch.
 *
 * The *sentence* is search's own. The library being empty and search having nothing to suggest
 * are the same cause and two different disappointments, and a reader on the search page told
 * "your library is empty" would be being answered about a screen they are not on.
 *
 * Hand-composed rather than a port of iOS's `ContentUnavailableView`, per divergence #12:
 * Material publishes no empty-state component. The content model is the same, and so are the
 * words. It scrolls, and the sentence is width-limited, because at the largest accessibility
 * text size it is taller than the screen — which is what [HomeFirstRun] learned on the surface
 * next door.
 */
@Composable
private fun SearchNothingToSuggest(
    scope: LibraryAvailability,
    onScopeChange: (LibraryAvailability) -> Unit,
    onOpenComic: () -> Unit,
    onAddFolder: () -> Unit,
    onAddCatalogue: () -> Unit,
    onAddKavita: () -> Unit,
    onAddShare: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(bottom = StoryArcSpace.xl),
    ) {
        // Stated even here. A reader who has narrowed to what is on the device and finds
        // nothing to suggest needs to be able to see the narrowing, or the empty page is
        // telling them something untrue about their library.
        item(key = "scope") { ScopeChips(scope, onScopeChange) }

        item(key = "sentence") {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xl),
                verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
            ) {
                Text(
                    text = stringResource(R.string.search_empty_title),
                    style = MaterialTheme.typography.headlineSmall,
                    color = palette.textPrimary,
                )
                Text(
                    text = stringResource(R.string.search_empty_subtitle),
                    style = MaterialTheme.typography.bodyLarge,
                    color = palette.textSecondary,
                    modifier = Modifier
                        .widthIn(max = FIRST_RUN_MEASURE)
                        .padding(bottom = StoryArcSpace.sm),
                )
                Button(onClick = onOpenComic) {
                    Text(stringResource(R.string.library_open_comic))
                }
                // Plain, and second, for the reason `HomeFirstRun` gives: a reader who has
                // just installed a comic app wants to read a comic, and the shelf full of
                // them can wait until they know the app opens one.
                SearchAddSourceMenu(
                    onOpenComic = onOpenComic,
                    onAddFolder = onAddFolder,
                    onAddCatalogue = onAddCatalogue,
                    onAddKavita = onAddKavita,
                    onAddShare = onAddShare,
                )
            }
        }
    }
}

/**
 * The five kinds of place, one level down — the same five `EmptyLibrary` offers.
 *
 * A labelled button rather than the toolbar's plus glyph, per `sources`' *plain secondary
 * action*: on a screen with nothing on it a reader has nothing to compare a lone icon against.
 * The transports are named only inside the menu, where choosing between them is the question
 * actually being asked rather than a wall to be understood first.
 */
@Composable
private fun SearchAddSourceMenu(
    onOpenComic: () -> Unit,
    onAddFolder: () -> Unit,
    onAddCatalogue: () -> Unit,
    onAddKavita: () -> Unit,
    onAddShare: () -> Unit,
) {
    var open by remember { mutableStateOf(false) }

    TextButton(onClick = { open = true }) {
        Text(stringResource(R.string.library_add_source))
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        SearchAddSourceItem(R.string.library_add_folder, Icons.Filled.CreateNewFolder) {
            open = false
            onAddFolder()
        }
        // Beside the source kinds rather than among them: `local-library` gives imported
        // copies a requirement of their own, and "On this device" is not a place a reader
        // configures.
        SearchAddSourceItem(R.string.library_import, Icons.Filled.FileDownload) {
            open = false
            onOpenComic()
        }
        SearchAddSourceItem(R.string.catalogue_title, Icons.Filled.RssFeed) {
            open = false
            onAddCatalogue()
        }
        SearchAddSourceItem(R.string.kavita_title, Icons.Filled.Dns) {
            open = false
            onAddKavita()
        }
        SearchAddSourceItem(R.string.smb_title, Icons.Filled.Storage) {
            open = false
            onAddShare()
        }
    }
}

@Composable
private fun SearchAddSourceItem(label: Int, icon: ImageVector, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(stringResource(label)) },
        leadingIcon = { Icon(icon, contentDescription = null) },
        onClick = onClick,
    )
}
