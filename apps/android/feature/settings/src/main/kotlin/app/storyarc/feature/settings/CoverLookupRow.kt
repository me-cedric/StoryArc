package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.coverLookupServiceNames

/**
 * The one switch that lets a cover request leave the device.
 *
 * On the Privacy screen rather than beside the other reading settings, because what it
 * changes is where data goes. `cover-art` requires the app to "name the provider it would
 * ask" before a reader turns it on, so the row states all three and the sentence under it
 * states what travels: one identifier, and nothing else.
 *
 * iOS's `CoverLookupSettings` draws the same row on the same screen.
 */
@Composable
internal fun CoverLookupRow(
    settings: AppSettings,
    onChange: (AppSettings) -> Unit,
    modifier: Modifier = Modifier,
    highlight: SettingsAnchor? = null,
) {
    val palette = LocalStoryArcPalette.current
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.hair),
    ) {
        SettingsSwitchRow(
            title = stringResource(R.string.covers_lookup),
            note = stringResource(R.string.covers_lookup_providers, coverLookupProviderNames()),
            checked = settings.lookUpMissingCovers,
            onChange = { onChange(settings.copy(lookUpMissingCovers = it)) },
            modifier = Modifier.settingsHighlight(SettingsAnchor.COVER_LOOKUP, highlight),
        )
        Text(
            text = stringResource(R.string.covers_lookup_note),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
        )
    }
}

/**
 * Every service the switch lets the app ask, written out for the reader.
 *
 * Both the identifier lookup and the title search: one switch gates both, so the row names
 * both. Joined with a comma rather than a localised list format: these are the services' own
 * names, and the row's job is to let a reader recognise them. A function rather than a
 * literal, so a test can assert the row names every service the switch opens -- one added
 * without a word on this screen would be a request a reader never agreed to.
 */
internal fun coverLookupProviderNames(): String = coverLookupServiceNames.joinToString(", ")
