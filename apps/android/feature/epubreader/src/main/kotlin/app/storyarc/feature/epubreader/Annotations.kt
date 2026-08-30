package app.storyarc.feature.epubreader

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.swatch
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Annotation
import app.storyarc.core.model.AnnotationExport

/**
 * Everything a reader marked, in one place.
 *
 * `ebook-reader`: "highlights and notes are listed in one place and exportable as plain text
 * or Markdown". One list, because a note is a highlight with something written on it -- two
 * lists would be the app insisting on a distinction the reader did not make.
 *
 * iOS's `AnnotationList` draws the same rows.
 */
@Composable
internal fun Annotations(
    annotations: List<Annotation>,
    onGo: (Annotation) -> Unit,
    onEdit: (Annotation) -> Unit,
    onRemove: (Annotation) -> Unit,
    onExport: (AnnotationExport.Format) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    if (annotations.isEmpty()) {
        Column(
            modifier = modifier.fillMaxWidth().padding(StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            Text(
                text = stringResource(R.string.annotations_title),
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
            )
            // Says what the control is rather than that there is nothing: a reader who has
            // never selected a word has no reason to know a menu appears when they do.
            Text(
                text = stringResource(R.string.annotations_empty),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
        return
    }

    Column(modifier = modifier.fillMaxWidth()) {
        LazyColumn(
            modifier = Modifier.fillMaxWidth().heightIn(max = 360.dp),
            contentPadding = PaddingValues(bottom = StoryArcSpace.sm),
        ) {
            items(annotations, key = { it.id }) { annotation ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(role = Role.Button) { onGo(annotation) }
                        .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.sm),
                    horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
                ) {
                    // The colour as a rule down the side rather than a dot: it is the mark's
                    // identity, and a reader scanning is looking for "the green ones".
                    Column(
                        modifier = Modifier
                            .width(4.dp)
                            .height(44.dp)
                            .background(annotation.colour.swatch, RoundedCornerShape(2.dp)),
                    ) {}

                    Column(modifier = Modifier.weight(1f)) {
                        if (annotation.chapter.isNotBlank()) {
                            Text(
                                text = annotation.chapter,
                                style = MaterialTheme.typography.labelMedium,
                                color = palette.textSecondary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Text(
                            text = annotation.text,
                            style = MaterialTheme.typography.bodyMedium,
                            color = palette.textPrimary,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                        )
                        if (annotation.hasNote) {
                            Text(
                                text = annotation.note,
                                style = MaterialTheme.typography.bodySmall,
                                color = palette.textSecondary,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }

                    IconButton(onClick = { onEdit(annotation) }) {
                        Icon(
                            Icons.Filled.Edit,
                            contentDescription = stringResource(R.string.annotations_note),
                            tint = palette.textSecondary,
                        )
                    }
                    IconButton(onClick = { onRemove(annotation) }) {
                        Icon(
                            Icons.Filled.Delete,
                            contentDescription = stringResource(R.string.annotations_remove),
                            tint = palette.textSecondary,
                        )
                    }
                }
            }
        }

        // Both formats side by side, because the spec offers both and choosing one is
        // choosing where you are about to paste it.
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = StoryArcSpace.gutter),
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = { onExport(AnnotationExport.Format.PLAIN_TEXT) }) {
                Text(stringResource(R.string.annotations_export_text))
            }
            TextButton(onClick = { onExport(AnnotationExport.Format.MARKDOWN) }) {
                Text(stringResource(R.string.annotations_export_markdown))
            }
        }
    }
}
