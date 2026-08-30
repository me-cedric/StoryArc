package app.storyarc.feature.library

import android.text.format.DateUtils
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.SourceRegistry

/**
 * States that the shelf on screen is last session's, and when it was confirmed.
 *
 * `sources` asks for "a single unobtrusive indicator" saying "that content is cached and
 * when it was last refreshed". One line, in the secondary text colour, that leaves as soon
 * as a walk finishes — at which point the shelf is not cached, it is current, and a notice
 * still claiming otherwise would be the indicator lying quietly in the corner.
 *
 * Not an error and not a warning. Offline is a normal state; so is a library that has not
 * been rewalked yet. iOS shows the same line above its grid, from `CachedNotice`.
 */
@Composable
internal fun CachedNotice(refreshedAtEpochMillis: Long) {
    val palette = LocalStoryArcPalette.current
    // The platform's own phrasing for "twelve minutes ago", which `localization` requires
    // rather than a string this app assembles and then has to translate four times.
    val relative = DateUtils.getRelativeTimeSpanString(
        refreshedAtEpochMillis,
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS,
    ).toString()

    Text(
        text = stringResource(R.string.library_cached, relative),
        style = MaterialTheme.typography.labelLarge,
        color = palette.textSecondary,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xs),
    )
}

/**
 * The first thing a reader ever sees when they own nothing.
 *
 * `sources`, the *Adding the first source* scenario, states the whole of it: "one sentence
 * in plain language, one primary action that opens a comic from the device with nothing to
 * configure first, and one plain secondary action that leads to connecting a library", and
 * "the four source types are named only after that secondary action is taken".
 *
 * What stood here — in `LibraryScreen.kt`, which is over the module's line cap and is why
 * this moved — was the opposite of every clause of that: four rows, one per transport,
 * three of them meaningless to the person reading them, over a primary button that read
 * *Refresh the library* while actually opening the folder picker, because one string served
 * both it and the toolbar's refresh icon.
 *
 * Hand-composed rather than a port of iOS's `ContentUnavailableView`, per divergence #12:
 * Material publishes no empty-state component, and importing iOS's shape is the
 * cross-platform habit this revamp is undoing. The *content model* is the same, and so are
 * the words.
 */
@Composable
internal fun EmptyLibrary(
    /** Copies one file in and opens it. Configures nothing, remembers nothing else. */
    onOpenComic: () -> Unit,
    onAddFolder: () -> Unit,
    onAddCatalogue: () -> Unit,
    onAddKavita: () -> Unit,
    onAddShare: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xxl),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        Text(
            text = stringResource(R.string.library_empty_title),
            style = MaterialTheme.typography.headlineSmall,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(R.string.library_empty_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textSecondary,
            modifier = Modifier
                .widthIn(max = FIRST_RUN_MEASURE)
                .padding(bottom = StoryArcSpace.sm),
        )
        Button(onClick = onOpenComic) {
            Text(stringResource(R.string.library_open_comic))
        }
        // Plain, and second: a reader who has just installed a comic app wants to read a
        // comic, and the shelf full of them can wait until they know the app opens one.
        AddBooksButton(
            onAddFolder = onAddFolder,
            onOpenComic = onOpenComic,
            onAddCatalogue = onAddCatalogue,
            onAddKavita = onAddKavita,
            onAddShare = onAddShare,
        )
    }
}

/**
 * Sources are configured, and the shelf still has nothing on it.
 *
 * Two ways to arrive, and they are not the same fact, so they do not get the same sentence:
 * either nothing the reader added can be reached, or the places are answering and have sent
 * nothing to this device yet. Telling a reader on a train that their library is empty would
 * be a lie about their books; telling a reader with a fresh, reachable server that nothing
 * can be reached would be a lie about their network.
 *
 * What stood here was the source list — the configured sources, their connection states and
 * a coloured dot each. That is the plumbing wearing the shelf's clothes, and §6.2 of the
 * design direction puts connections in Settings and nowhere else on the browse path. They
 * are still there, with the same removal flow.
 *
 * Never a dead end: one action asks every source again, one opens a comic that needs no
 * source at all. Offline is a normal state, so neither sentence is an error and neither is
 * red — see AGENTS.md §2. iOS shows the same pair from `LibraryAway`.
 */
@Composable
internal fun LibraryAway(
    isEverythingAway: Boolean,
    onRetry: () -> Unit,
    onOpenComic: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xxl),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
    ) {
        Text(
            text = stringResource(R.string.library_empty_title),
            style = MaterialTheme.typography.headlineSmall,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(
                if (isEverythingAway) R.string.library_away_body else R.string.library_pending_body,
            ),
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textSecondary,
            modifier = Modifier
                .widthIn(max = FIRST_RUN_MEASURE)
                .padding(bottom = StoryArcSpace.sm),
        )
        Button(onClick = onRetry) {
            Text(stringResource(R.string.source_offline_retry))
        }
        TextButton(onClick = onOpenComic) {
            Text(stringResource(R.string.library_open_comic))
        }
    }
}

/**
 * The four kinds of place, one level down.
 *
 * A labelled button rather than the toolbar's plus glyph: on an empty screen the reader has
 * nothing to compare a lone icon against, and `sources` asks for a *plain secondary action*,
 * which is a thing with words on it. What it opens is the same five choices the toolbar
 * offers, and the four transports are named only here — where choosing between them is the
 * question actually being asked, rather than a wall to be understood first.
 */
@Composable
private fun AddBooksButton(
    onAddFolder: () -> Unit,
    onOpenComic: () -> Unit,
    onAddCatalogue: () -> Unit,
    onAddKavita: () -> Unit,
    onAddShare: () -> Unit,
) {
    var open by remember { mutableStateOf(false) }

    TextButton(onClick = { open = true }) {
        Text(stringResource(R.string.library_add_source))
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        AddBooksItem(R.string.library_add_folder, Icons.Filled.CreateNewFolder) {
            open = false
            onAddFolder()
        }
        AddBooksItem(R.string.library_import, Icons.Filled.FileDownload) {
            open = false
            onOpenComic()
        }
        AddBooksItem(R.string.catalogue_title, Icons.Filled.RssFeed) {
            open = false
            onAddCatalogue()
        }
        AddBooksItem(R.string.kavita_title, Icons.Filled.Dns) {
            open = false
            onAddKavita()
        }
        AddBooksItem(R.string.smb_title, Icons.Filled.Storage) {
            open = false
            onAddShare()
        }
    }
}

@Composable
private fun AddBooksItem(
    label: Int,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(stringResource(label)) },
        leadingIcon = { Icon(icon, contentDescription = null) },
        onClick = onClick,
    )
}

/**
 * Whether nothing the reader added can be reached.
 *
 * A function rather than a line inside the composable so the branch can be asserted without
 * a device: which of [LibraryAway]'s two sentences a reader is shown is the whole substance
 * of that screen. A local folder is marked connected the moment it is added, so a
 * configured folder makes this false — which is right, because a folder with nothing in it
 * has not gone away, it is empty, and those are two different sentences.
 *
 * iOS answers the same question in `LibraryAway.everythingAway(in:)`.
 */
internal fun everythingAway(registry: SourceRegistry): Boolean =
    registry.sources.isNotEmpty() && registry.sources.none { it.state.canFetch }

/**
 * How wide a first-run sentence is allowed to run.
 *
 * A tablet would otherwise set one line across the whole window, which is the measure this
 * app spends the rest of its effort avoiding.
 */
private val FIRST_RUN_MEASURE = 520.dp
