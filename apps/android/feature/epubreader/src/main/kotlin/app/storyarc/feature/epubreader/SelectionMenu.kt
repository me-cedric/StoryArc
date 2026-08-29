package app.storyarc.feature.epubreader

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.HighlightColour

/**
 * The menu a selection gets.
 *
 * `ebook-reader`: on a selection, "highlight in several colours, add a note, copy, and
 * search-in-publication are offered". The platform's own text-selection toolbar is a row of
 * verbs and has nowhere to put five colours, so this is shown instead.
 *
 * iOS's `SelectionMenu` offers the same four things.
 */
@Composable
internal fun SelectionMenu(
    onHighlight: (HighlightColour) -> Unit,
    onNote: () -> Unit,
    onCopy: () -> Unit,
    onSearch: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Surface(
        modifier = modifier,
        shape = androidx.compose.foundation.shape.RoundedCornerShape(StoryArcRadius.lg),
        color = palette.surfaceRaised,
        tonalElevation = 3.dp,
    ) {
        Column(
            modifier = Modifier.padding(StoryArcSpace.md),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
                HighlightColour.entries.forEach { colour ->
                    val name = stringResource(colour.labelRes)
                    Column(
                        modifier = Modifier
                            .size(44.dp)
                            .clickable(onClickLabel = name) { onHighlight(colour) },
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Column(
                            modifier = Modifier
                                .size(28.dp)
                                .background(colour.swatch, CircleShape)
                                .border(0.5.dp, palette.textTertiary, CircleShape),
                        ) {}
                    }
                }
            }

            HorizontalDivider()

            Row(horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.lg)) {
                IconButton(onClick = onNote) {
                    Icon(
                        Icons.Filled.Edit,
                        contentDescription = stringResource(R.string.annotations_note),
                        tint = palette.textPrimary,
                    )
                }
                IconButton(onClick = onCopy) {
                    Icon(
                        Icons.Filled.ContentCopy,
                        contentDescription = stringResource(R.string.annotations_copy),
                        tint = palette.textPrimary,
                    )
                }
                IconButton(onClick = onSearch) {
                    Icon(
                        Icons.Filled.Search,
                        contentDescription = stringResource(R.string.epub_search),
                        tint = palette.textPrimary,
                    )
                }
            }
        }
    }
}

/**
 * What the colour looks like on a page.
 *
 * Fixed hues rather than palette tokens: a highlight is ink a reader chose, and one that
 * changed colour when they changed theme would stop meaning what they meant by it. iOS's
 * `swatch` is the same five.
 */
internal val HighlightColour.swatch: Color
    get() = when (this) {
        HighlightColour.YELLOW -> Color(0xFFFFD940)
        HighlightColour.GREEN -> Color(0xFF73D973)
        HighlightColour.BLUE -> Color(0xFF66B8FF)
        HighlightColour.PINK -> Color(0xFFFF8CBF)
        HighlightColour.PURPLE -> Color(0xFFB88CFF)
    }

/** Named, not described: a reader picking a colour needs "yellow", not "the first swatch". */
internal val HighlightColour.labelRes: Int
    get() = when (this) {
        HighlightColour.YELLOW -> R.string.annotations_colour_yellow
        HighlightColour.GREEN -> R.string.annotations_colour_green
        HighlightColour.BLUE -> R.string.annotations_colour_blue
        HighlightColour.PINK -> R.string.annotations_colour_pink
        HighlightColour.PURPLE -> R.string.annotations_colour_purple
    }
