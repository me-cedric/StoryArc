package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source

/**
 * The libraries a reader has added, when none of them has given the shelf anything yet.
 *
 * Not a browse surface: it is what stands in for the grid while a first walk or a first
 * connection is still owed, and it is the only place in the browse path that names a
 * library one by one.
 */
@Composable
internal fun SourceList(
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
        contentPadding = PaddingValues(StoryArcSpace.gutter),
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
