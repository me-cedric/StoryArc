package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.CertificatePinNotice
import app.storyarc.core.model.ImportPreviewLine
import app.storyarc.core.model.ImportedShelf

/**
 * The whole preview: one block per line of the plan, in the order the plan gives them.
 *
 * `library-portability` / *The reader sees what will happen first*. iOS's `ImportPreviewList`
 * draws the same lines in the same order.
 */
@Composable
internal fun ImportPreviewList(lines: List<ImportPreviewLine>, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.md)) {
        lines.forEach { ImportPreviewLineRows(it) }
    }
}

/** One line of the import preview: a sentence, and the names it counts. */
@Composable
internal fun ImportPreviewLineRows(line: ImportPreviewLine, modifier: Modifier = Modifier) {
    when (line) {
        is ImportPreviewLine.CertificatePins -> PinRows(line.pins, modifier)
        is ImportPreviewLine.SourcesToAdd ->
            Named(pluralStringResource(R.plurals.transfer_line_sources, line.names.size, line.names.size), line.names, modifier)
        is ImportPreviewLine.SourcesNeedingSignIn ->
            Named(pluralStringResource(R.plurals.transfer_line_sign_in, line.names.size, line.names.size), line.names, modifier)
        is ImportPreviewLine.ShelvesToAdd ->
            Named(pluralStringResource(R.plurals.transfer_line_shelves, line.names.size, line.names.size), line.names, modifier)
        is ImportPreviewLine.ShelvesMerged -> MergedShelfRows(line.shelves, modifier)
        is ImportPreviewLine.Progress -> Column(modifier, Arrangement.spacedBy(StoryArcSpace.xs)) {
            if (line.add > 0) {
                Sentence(pluralStringResource(R.plurals.transfer_line_progress_add, line.add, line.add))
            }
            if (line.merge > 0) {
                Sentence(pluralStringResource(R.plurals.transfer_line_progress_merge, line.merge, line.merge))
            }
        }
        is ImportPreviewLine.Themes ->
            Sentence(pluralStringResource(R.plurals.transfer_line_themes, line.count, line.count), modifier)
        is ImportPreviewLine.Covers ->
            Sentence(pluralStringResource(R.plurals.transfer_line_covers, line.count, line.count), modifier)
        ImportPreviewLine.SettingsChange -> Sentence(stringResource(R.string.transfer_line_settings), modifier)
        ImportPreviewLine.NothingNew -> Sentence(stringResource(R.string.transfer_line_nothing), modifier)
    }
}

@Composable
private fun Sentence(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = LocalStoryArcPalette.current.textPrimary,
        modifier = modifier,
    )
}

/** A header sentence and the names it counts, one to a line. */
@Composable
private fun Named(header: String, names: List<String>, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair)) {
        Text(
            text = header,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        names.forEach {
            Text(text = it, style = MaterialTheme.typography.labelLarge, color = palette.textSecondary)
        }
    }
}

/**
 * A change to what the app trusts, so it is flagged apart from the changes to what the reader
 * owns and explained under the list. The icon carries the flag as well as the colour, so it does
 * not rest on colour alone.
 */
@Composable
private fun PinRows(pins: List<CertificatePinNotice>, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs)) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(20.dp),
            )
            Text(
                text = stringResource(R.string.transfer_line_pins),
                style = MaterialTheme.typography.titleSmall,
                color = palette.textPrimary,
                modifier = Modifier.semantics { heading() },
            )
        }
        pins.forEach { PinRow(it) }
        Text(
            text = stringResource(R.string.transfer_line_pins_note),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
        )
    }
}

/** A host that gains a pinned certificate, and the source it arrived with. */
@Composable
internal fun PinRow(pin: CertificatePinNotice, modifier: Modifier = Modifier) {
    Text(
        text = pin.sourceName?.let { stringResource(R.string.transfer_line_pin, pin.host, it) }
            ?: stringResource(R.string.transfer_line_pin_alone, pin.host),
        style = MaterialTheme.typography.bodyMedium,
        color = LocalStoryArcPalette.current.textPrimary,
        modifier = modifier,
    )
}

@Composable
private fun MergedShelfRows(shelves: List<ImportedShelf>, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs)) {
        Sentence(pluralStringResource(R.plurals.transfer_line_merged, shelves.size, shelves.size))
        shelves.forEach { MergedShelfRow(it) }
    }
}

/** A shelf on both sides, and how many members the import adds to it. */
@Composable
internal fun MergedShelfRow(shelf: ImportedShelf, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = modifier.semantics(mergeDescendants = true) {},
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
    ) {
        Text(text = shelf.name, style = MaterialTheme.typography.bodyMedium, color = palette.textPrimary)
        Text(
            text = pluralStringResource(
                R.plurals.transfer_line_merged_added,
                shelf.membersAdded,
                shelf.membersAdded,
            ),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
        )
    }
}
