package app.storyarc.feature.reader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Annotation
import app.storyarc.core.persistence.AnnotationStore

/**
 * The page bookmarks of a fixed-page publication with no text layer -- a comic, or a
 * scan (D8). A PDF's own marks keep [PdfTextSheet]'s marks panel; this is what a reader
 * sees instead when there are no words to have selected one from.
 */
@Composable
internal fun ComicBookmarkSheet(
    annotations: List<Annotation>,
    onGo: (Int) -> Unit,
    onRemove: (Annotation) -> Unit,
) {
    if (annotations.isEmpty()) {
        Text(
            text = stringResource(R.string.reader_bookmark_empty),
            style = MaterialTheme.typography.bodySmall,
            color = LocalStoryArcPalette.current.textSecondary,
            modifier = Modifier.fillMaxWidth().padding(StoryArcSpace.gutter),
        )
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxWidth().heightIn(max = 340.dp),
        contentPadding = PaddingValues(bottom = StoryArcSpace.sm),
    ) {
        items(annotations, key = { it.id }) { annotation ->
            ListItem(
                trailingContent = {
                    TextButton(onClick = { onRemove(annotation) }) {
                        Text(stringResource(R.string.reader_pdf_marks_remove))
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button) {
                        ComicPageBookmark.pageIndexOf(annotation)?.let(onGo)
                    },
            ) { Text(annotation.text) }
        }
    }
}

/**
 * D8: "bookmark the current page", for a comic or a scan -- neither has words to select,
 * which is how a PDF with text marks one instead.
 */
@Composable
internal fun BookmarkThisPageRow(onClick: () -> Unit) {
    // A leading icon like every other row in the menu. Outlined, so it reads apart from
    // the Bookmarks row's filled one just above it.
    ListItem(
        leadingContent = { Icon(imageVector = Icons.Outlined.BookmarkBorder, contentDescription = null) },
        modifier = Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick),
    ) { Text(stringResource(R.string.reader_bookmark_add)) }
}

/** A publication's page bookmarks, refreshed after every change made through it. */
internal class ComicBookmarksHolder(private val store: AnnotationStore?, private val publication: String) {
    var annotations by mutableStateOf(store?.annotations(publication).orEmpty())
        private set

    fun add(pageIndex: Int, pageCount: Int, pageLabel: (Int) -> String) {
        ComicPageBookmark.add(pageIndex, pageCount, store, publication, pageLabel)
        annotations = store?.annotations(publication).orEmpty()
    }

    fun remove(annotation: Annotation) {
        annotations = store?.remove(annotation.id, publication).orEmpty()
    }
}

@Composable
internal fun rememberComicBookmarks(store: AnnotationStore?, publication: String): ComicBookmarksHolder =
    remember(store, publication) { ComicBookmarksHolder(store, publication) }
