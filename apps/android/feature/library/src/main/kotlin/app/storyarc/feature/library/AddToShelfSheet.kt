package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication

/**
 * Where a publication can be put.
 *
 * `collections-and-reading-lists`: "a publication may belong to any number of collections".
 * So this offers every one of them rather than a picker that implies a single answer, and
 * says so plainly when there is nowhere to put it yet.
 *
 * iOS puts the same choice in a context menu, which is where iOS readers look.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun AddToShelfSheet(
    viewModel: LibraryViewModel,
    publication: Publication,
    onDismiss: () -> Unit,
) {
    val palette = LocalStoryArcPalette.current
    val shelves by viewModel.shelves.collectAsStateWithLifecycle()
    val already = shelves.collectionsContaining(publication.id).map { it.id }.toSet()

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .padding(horizontal = StoryArcSpace.gutter)
                .padding(bottom = StoryArcSpace.xl),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        ) {
            Text(
                text = stringResource(R.string.shelves_add_to),
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
                modifier = Modifier.padding(bottom = StoryArcSpace.sm),
            )

            if (shelves.collections.isEmpty() && shelves.lists.isEmpty()) {
                Text(
                    text = stringResource(R.string.shelves_collections_none),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textSecondary,
                )
            }

            shelves.collections.forEach { collection ->
                val contains = collection.id in already
                Row(
                    name = collection.name,
                    isMember = contains,
                    enabled = !contains,
                ) {
                    viewModel.addToCollection(setOf(publication.id), collection.id)
                    onDismiss()
                }
            }

            shelves.lists.forEach { list ->
                val contains = publication.id in list.entries
                Row(
                    name = list.name,
                    isMember = contains,
                    enabled = !contains,
                ) {
                    viewModel.appendToList(listOf(publication.id), list.id)
                    onDismiss()
                }
            }
        }
    }
}

@Composable
private fun Row(name: String, isMember: Boolean, enabled: Boolean, onTap: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Text(
        text = if (isMember) "$name ✓" else name,
        style = MaterialTheme.typography.bodyLarge,
        color = if (enabled) palette.textPrimary else palette.textTertiary,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onTap)
            .defaultMinSize(minHeight = 48.dp)
            .padding(vertical = StoryArcSpace.sm),
    )
}
