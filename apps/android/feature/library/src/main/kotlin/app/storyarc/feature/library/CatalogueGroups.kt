package app.storyarc.feature.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsGroup
import app.storyarc.core.catalogue.OpdsSection
import app.storyarc.core.designsystem.grid.steppedForFontScale
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcRadius
import app.storyarc.core.designsystem.tokens.StoryArcSpace

/**
 * One named run of a catalogue, shown as the feed declared it.
 *
 * `opds-catalog` browses what the server says, and an OPDS 2.0 server says "Recently added"
 * and "Staff picks" are two things. Poured into one grid they were neither: the titles
 * vanished and the reader got an undivided run of covers in whatever order the groups
 * happened to be serialised in.
 *
 * A row rather than a grid, because a group is a *sample* -- the feed sends the first handful
 * and a link to the rest, and a full-width grid of six covers would claim the group has six
 * things in it. iOS's `CatalogueGroupSection` is the same section.
 */
@Composable
internal fun CatalogueGroupSection(
    group: OpdsGroup,
    credential: OpdsCredential?,
    client: OpdsClient,
    onDevice: Set<String>,
    onEnter: (title: String, url: String) -> Unit,
    onSelect: (OpdsEntry) -> Unit,
    onDownload: (OpdsEntry) -> Unit,
    onRemove: (OpdsEntry) -> Unit,
) {
    val palette = LocalStoryArcPalette.current

    Column(verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = group.title,
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
                modifier = Modifier.weight(1f),
            )

            // Only where the group says where the rest of it is. A "see all" that led back to
            // the page it is already on is a control that does nothing.
            group.more?.let { rest ->
                TextButton(onClick = { onEnter(group.title, rest) }) {
                    Text(stringResource(R.string.catalogue_group_more))
                }
            }
        }

        // A group can hold sections as well as publications -- the standard lets it hold
        // whatever a feed holds -- so both are shown rather than only the one a catalogue
        // happens to use most.
        group.navigation.forEach { section ->
            CatalogueSectionRow(section) { onEnter(section.title, section.href) }
        }

        if (group.publications.isNotEmpty()) {
            // A sample's cover keeps a width of its own — this is a row, not a grid, like the
            // continue-reading run — and steps with the reader's text size as every cover
            // does; `design.md` §4.
            val cellWidth = catalogueGroupCoverWidth(LocalDensity.current.fontScale)
            LazyRow(
                horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
                contentPadding = PaddingValues(vertical = StoryArcSpace.hair),
            ) {
                items(group.publications, key = { it.id }) { entry ->
                    CatalogueEntryCell(
                        entry = entry,
                        credential = credential,
                        client = client,
                        isDownloaded = entry.id in onDevice,
                        onSelect = { onSelect(entry) },
                        onDownload = { onDownload(entry) },
                        onRemove = { onRemove(entry) },
                        modifier = Modifier.width(cellWidth),
                    )
                }
            }
        }
    }
}

/** How wide a cover in a group's row is at an ordinary text size. */
private val GROUP_COVER_WIDTH = 140.dp

/**
 * How wide a cover in a group's row is, for this reader: 140 dp, or 196 past the ordinary
 * range.
 *
 * A width of its own, as every horizontal run of covers in the app has, and the ladder's
 * step, which this row had missed: the catalogue's grid one tap away widened at an
 * accessibility text size and its front-page samples did not. Pure, so `CoverLadderStepTest`
 * can assert it without a feed.
 */
internal fun catalogueGroupCoverWidth(fontScale: Float): Dp =
    GROUP_COVER_WIDTH.steppedForFontScale(fontScale)

/** A section, with its count where the feed gave one. */
@Composable
internal fun CatalogueSectionRow(section: OpdsSection, onEnter: () -> Unit) {
    val palette = LocalStoryArcPalette.current
    Surface(
        color = palette.surfaceRaised,
        shape = RoundedCornerShape(StoryArcRadius.lg),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onEnter),
    ) {
        Column(modifier = Modifier.padding(StoryArcSpace.md)) {
            Text(
                text = section.title,
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
            )
            section.count?.let { count ->
                Text(
                    text = pluralStringResource(R.plurals.catalogue_section_count, count, count),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }
        }
    }
}
