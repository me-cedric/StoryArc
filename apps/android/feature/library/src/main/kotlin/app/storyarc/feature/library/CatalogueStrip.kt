package app.storyarc.feature.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.RssFeed
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source

/**
 * The catalogues a reader has added, as a row of ways in.
 *
 * A strip rather than a list: most readers have none or one, and a full-width section for a
 * single row would push the library down for everybody. It scrolls horizontally for the
 * reader who collects them. iOS's `CatalogueStrip` is the same row.
 */
@Composable
fun CatalogueStrip(sources: List<Source>, onOpen: (Source) -> Unit) {
    val palette = LocalStoryArcPalette.current
    Row(
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        modifier = Modifier
            .fillMaxWidth()
            .background(palette.surfaceSunken)
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
    ) {
        val hint = stringResource(R.string.catalogue_strip_hint)
        sources.forEach { source ->
            Surface(
                color = palette.surfaceRaised,
                shape = CircleShape,
                modifier = Modifier
                    .clickable { onOpen(source) }
                    // 48dp is the floor `pnpm a11y:android` checks, and a chip is the
                    // control most likely to fall under it.
                    .defaultMinSize(minHeight = 48.dp)
                    .semantics { contentDescription = "${source.displayName}. $hint" },
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
                    modifier = Modifier.padding(
                        horizontal = StoryArcSpace.md,
                        vertical = StoryArcSpace.sm,
                    ),
                ) {
                    Icon(Icons.Filled.RssFeed, contentDescription = null, tint = palette.accent)
                    Text(
                        text = source.displayName,
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Icon(
                        Icons.Filled.ChevronRight,
                        contentDescription = null,
                        tint = palette.textTertiary,
                    )
                }
            }
        }
    }
}

/** The two ways to add a source that exist, behind one button. */
@Composable
fun AddSourceMenu(onAddFolder: () -> Unit, onAddCatalogue: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    var open by remember { mutableStateOf(false) }

    IconButton(onClick = { open = true }) {
        Icon(
            imageVector = Icons.Filled.Add,
            contentDescription = stringResource(R.string.library_add_source),
            tint = palette.accent,
        )
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.library_add_folder)) },
            leadingIcon = { Icon(Icons.Filled.CreateNewFolder, contentDescription = null) },
            onClick = {
                open = false
                onAddFolder()
            },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.catalogue_title)) },
            leadingIcon = { Icon(Icons.Filled.RssFeed, contentDescription = null) },
            onClick = {
                open = false
                onAddCatalogue()
            },
        )
    }
}
