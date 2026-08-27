package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind

/**
 * Every configured source, and what can be done to one.
 *
 * `sources` requires the registry to be reachable, and until now it was not: the library's
 * own source list only appears in a corner of its empty state, and this group said "not
 * built yet". The registry existed and nothing showed it.
 *
 * Handed its data rather than owning it. A feature module never depends on another feature
 * module (docs/architecture), and the registry belongs to the library — so the app layer
 * passes it through and takes the removal back.
 *
 * The icon and the state wording are mapped here rather than shared with the library's
 * own mapping, for the reason that file gives: the domain enums live in `:core:model` and
 * carry no resources, so each feature names them in its own strings.
 */
@Composable
internal fun SourcesGroup(
    sources: List<Source>,
    itemCount: (Source) -> Int,
    onRemove: (Source) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    var removing by remember { mutableStateOf<Source?>(null) }

    removing?.let { source ->
        AlertDialog(
            onDismissRequest = { removing = null },
            title = { Text(stringResource(R.string.sources_remove_title, source.displayName)) },
            // `sources` asks the app to state what removal frees before asking. For a
            // folder that is nothing, and saying so is the point: a reader must not have to
            // guess whether this deletes their comics.
            text = {
                Text(
                    pluralStringResource(
                        R.plurals.sources_remove_body,
                        itemCount(source),
                        itemCount(source),
                    ),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    onRemove(source)
                    removing = null
                }) {
                    Text(
                        text = stringResource(R.string.sources_remove),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { removing = null }) {
                    Text(stringResource(R.string.settings_cancel))
                }
            },
        )
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md)) {
        if (sources.isEmpty()) {
            // A reader with no source is not looking at a broken screen. `sources` wants the
            // app usable "in under ten seconds", and the library's empty state is where a
            // folder gets picked — so this points there rather than duplicating the picker.
            Text(
                text = stringResource(R.string.sources_none),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textSecondary,
            )
            return@Column
        }

        sources.forEach { source ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    // One control per row, announced once rather than as three unrelated
                    // pieces of text on the way past.
                    .semantics(mergeDescendants = true) {},
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(icon(source.kind), contentDescription = null, tint = palette.accent)

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
                ) {
                    Text(
                        text = source.displayName,
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textPrimary,
                    )
                    // The state and the count, which is what `sources` asks a source's own
                    // screen to show. Downloads are absent because nothing downloads yet,
                    // and the count is what exists in their place.
                    Text(
                        text = pluralStringResource(
                            R.plurals.sources_detail,
                            itemCount(source),
                            itemCount(source),
                        ),
                        style = MaterialTheme.typography.labelLarge,
                        color = palette.textTertiary,
                    )
                }

                Text(
                    text = stringResource(status(source.state)),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textTertiary,
                )

                IconButton(onClick = { removing = source }) {
                    Icon(
                        imageVector = Icons.Filled.Delete,
                        contentDescription = stringResource(
                            R.string.sources_remove_action,
                            source.displayName,
                        ),
                        tint = palette.textSecondary,
                    )
                }
            }
        }
    }
}

private fun icon(kind: SourceKind): ImageVector = when (kind) {
    SourceKind.LOCAL_FOLDER -> Icons.Filled.Folder
    SourceKind.NETWORK_SHARE -> Icons.Filled.Storage
    SourceKind.OPDS_CATALOG -> Icons.Filled.RssFeed
    SourceKind.KAVITA_SERVER -> Icons.Filled.Dns
}

private fun status(state: SourceConnectionState): Int = when (state) {
    is SourceConnectionState.Connected -> R.string.sources_state_connected
    is SourceConnectionState.Connecting -> R.string.sources_state_connecting
    is SourceConnectionState.Unreachable -> R.string.sources_state_unreachable
    is SourceConnectionState.Unauthorized -> R.string.sources_state_unauthorized
}
