package app.storyarc.feature.epubreader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BookmarkRemove
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Bookmark

/**
 * The places a reader marked, beside the publication's own navigation.
 *
 * `ebook-reader` puts bookmarks "alongside the table of contents", so they share the one
 * sheet and differ only by which tab is showing. A row states the chapter it falls in and
 * a little of the text there, which is what the spec asks a bookmark to be saved with --
 * and between them they are the only way to tell two marks apart, since a reflowable
 * publication has no page number to name.
 *
 * iOS's `BookmarkList` draws the same rows.
 */
@Composable
internal fun Bookmarks(
    bookmarks: List<Bookmark>,
    onGo: (Bookmark) -> Unit,
    onRemove: (Bookmark) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    if (bookmarks.isEmpty()) {
        Column(
            modifier = modifier.fillMaxWidth().padding(StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            Text(
                text = stringResource(R.string.epub_bookmarks),
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
            )
            // Says what the control is rather than that there is nothing, because a
            // reader who has never pressed it has no reason to know where it lives.
            Text(
                text = stringResource(R.string.epub_bookmarks_none),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
        return
    }

    LazyColumn(
        modifier = modifier.fillMaxWidth().heightIn(max = 420.dp),
        contentPadding = PaddingValues(bottom = StoryArcSpace.lg),
    ) {
        items(bookmarks, key = { it.id }) { bookmark ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button) { onGo(bookmark) }
                    .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = bookmark.chapter.ifBlank {
                            stringResource(R.string.epub_bookmark_unnamed)
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.textPrimary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    // Only when there is one. An empty second line would leave the rows
                    // different heights for a reason the reader cannot see.
                    if (bookmark.excerpt.isNotBlank()) {
                        Text(
                            text = bookmark.excerpt,
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.textSecondary,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }

                IconButton(onClick = { onRemove(bookmark) }) {
                    Icon(
                        imageVector = Icons.Filled.BookmarkRemove,
                        contentDescription = stringResource(R.string.epub_bookmark_remove),
                        tint = palette.textSecondary,
                    )
                }
            }
        }
    }
}
