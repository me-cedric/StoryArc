package app.storyarc.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.AppSettings
import java.util.Locale

/**
 * The four languages StoryArc speaks, and the option to follow the device.
 *
 * `localization`: "a user picks a language in settings" and "a 'System' option returns to
 * following the device". Each language names itself -- a reader looking for Deutsch is not
 * helped by a list that says "German" in a language they do not read.
 */
@Composable
internal fun LanguageGroup(
    settings: AppSettings,
    onChange: (AppSettings) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .selectableRow(selected = settings.language == null) {
                    onChange(settings.copy(language = null))
                }
                .padding(vertical = StoryArcSpace.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            RadioButton(selected = settings.language == null, onClick = null)
            Text(
                text = stringResource(R.string.settings_language_system),
                style = MaterialTheme.typography.bodyMedium,
                color = palette.textPrimary,
                modifier = Modifier.padding(start = StoryArcSpace.sm),
            )
        }

        SUPPORTED.forEach { tag ->
            val selected = settings.language == tag
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .selectableRow(selected = selected) { onChange(settings.copy(language = tag)) }
                    .padding(vertical = StoryArcSpace.xs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = selected, onClick = null)
                Text(
                    text = nameOf(tag),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.textPrimary,
                    modifier = Modifier.padding(start = StoryArcSpace.sm),
                )
            }
        }
    }
}

/** The tags `locales_config.xml` declares, in the order the reader sees them. */
private val SUPPORTED = listOf("en", "de", "es", "fr")

/** A language named in itself, capitalised the way that language capitalises it. */
private fun nameOf(tag: String): String {
    val locale = Locale.forLanguageTag(tag)
    return locale.getDisplayLanguage(locale).replaceFirstChar { it.titlecase(locale) }
}
