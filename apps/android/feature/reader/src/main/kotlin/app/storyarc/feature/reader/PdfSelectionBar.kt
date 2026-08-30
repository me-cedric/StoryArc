package app.storyarc.feature.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.theme.swatch
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.HighlightColour

/**
 * The menu a PDF selection gets.
 *
 * `ebook-reader`: on a selection, "highlight in several colours, add a note, copy, and
 * search-in-publication are offered". The same four the reflowable reader offers, in the same
 * order, because it is the same act -- what differs is only what is under the finger.
 *
 * A bar at the foot of the screen rather than the `ActionMode` the EPUB reader puts its colours
 * in. There is no text view here to raise one: the page is a bitmap, the selection is drawn by
 * this app, and a floating menu anchored to a rectangle the reader can zoom and pan would chase
 * it around the screen.
 *
 * iOS's `PdfSelectionMenu` offers the same four things.
 */
@Composable
internal fun PdfSelectionBar(
    text: String,
    onHighlight: (HighlightColour) -> Unit,
    onNote: () -> Unit,
    onCopy: () -> Unit,
    onSearch: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        color = LocalStoryArcPalette.current.scrim.copy(alpha = 0.85f),
        shape = RoundedCornerShape(StoryArcRadius.md),
        modifier = modifier.fillMaxWidth().padding(StoryArcSpace.md),
    ) {
        Column(
            modifier = Modifier.padding(StoryArcSpace.md),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            // The words themselves, so a reader who dragged past what they meant can see it
            // before they mark it.
            Text(
                text = text,
                style = MaterialTheme.typography.bodySmall,
                color = Color.White,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            ) {
                HighlightColour.entries.forEach { colour ->
                    val name = stringResource(colour.labelRes)
                    IconButton(
                        onClick = { onHighlight(colour) },
                        modifier = Modifier.semantics {
                            contentDescription = name
                            role = Role.Button
                        },
                    ) {
                        Box(
                            modifier = Modifier
                                .size(28.dp)
                                .background(colour.swatch, CircleShape)
                                .border(0.5.dp, Color.White.copy(alpha = 0.6f), CircleShape),
                        )
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                ) {
                    Action(Icons.Filled.EditNote, R.string.reader_pdf_note, onNote)
                    Action(Icons.Filled.ContentCopy, R.string.reader_pdf_copy, onCopy)
                    Action(Icons.Filled.Search, R.string.reader_pdf_search_selection, onSearch)
                    Action(Icons.Filled.Close, R.string.reader_pdf_deselect, onDismiss)
                }
            }
        }
    }
}

@Composable
private fun Action(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    labelRes: Int,
    onClick: () -> Unit,
) {
    IconButton(onClick = onClick) {
        Icon(
            imageVector = icon,
            contentDescription = stringResource(labelRes),
            tint = Color.White,
        )
    }
}

/**
 * Named, not described: a reader picking a colour needs "yellow", not "the first swatch".
 *
 * Its own strings in this module rather than the EPUB reader's. A module carries its own
 * catalogue, and `localization` requires every string in every language on both platforms rather
 * than one module reaching into another's resources.
 */
internal val HighlightColour.labelRes: Int
    get() = when (this) {
        HighlightColour.YELLOW -> R.string.reader_pdf_colour_yellow
        HighlightColour.GREEN -> R.string.reader_pdf_colour_green
        HighlightColour.BLUE -> R.string.reader_pdf_colour_blue
        HighlightColour.PINK -> R.string.reader_pdf_colour_pink
        HighlightColour.PURPLE -> R.string.reader_pdf_colour_purple
    }
