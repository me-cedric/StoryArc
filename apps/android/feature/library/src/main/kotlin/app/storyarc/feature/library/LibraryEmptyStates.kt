package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.LibraryQuery
import app.storyarc.core.model.SourceKind

/**
 * A library that has publications and is showing none of them.
 *
 * `library-browsing` forbids showing that silently: name what is narrowing the view and
 * offer one action to undo it. There are now four ways to arrive here and the message
 * names which one — a reader told "nothing matches the filters you set" when they set no
 * filter at all goes looking for a filter that does not exist.
 */
@Composable
internal fun NarrowedToNothing(
    query: LibraryQuery,
    onClear: () -> Unit,
    modifier: Modifier = Modifier,
    /** Whether the availability axis is the thing hiding everything. */
    isOnDeviceOnly: Boolean = false,
    /** Shows the whole library again. Null when the axis is already at its widest. */
    onWiden: (() -> Unit)? = null,
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
            text = when {
                term.isNotEmpty() -> stringResource(R.string.library_empty_search, term)
                isOnDeviceOnly -> stringResource(R.string.library_empty_on_device)
                else -> stringResource(R.string.library_empty_filtered)
            },
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
            textAlign = TextAlign.Center,
        )
        // Widening comes first: a reader who narrowed to what is on this device and found
        // nothing usually wants the rest of their library back, not their filters undone.
        if (onWiden != null) {
            Button(onClick = onWiden) { Text(stringResource(R.string.library_scope_all)) }
        }
        TextButton(onClick = onClear) { Text(stringResource(R.string.library_filter_clear)) }
    }
}

/**
 * A folder that was remembered and can no longer be read.
 *
 * `local-library`: name the folder and offer one action to pick it again. Never a
 * silent disappearance — a library that quietly loses half its rows looks broken
 * rather than disconnected.
 */
@Composable
internal fun UnavailableFolders(
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
internal fun Scanning(found: Int, modifier: Modifier = Modifier) {
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
