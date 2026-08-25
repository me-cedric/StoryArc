package app.storyarc.feature.settings

import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Palette
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import app.storyarc.core.model.AppSettings

/**
 * The seven groups `settings-and-about` names, in the order it names them.
 *
 * The order is the spec's and not alphabetical or arbitrary: Sources first because it is
 * what a new reader needs, About last because it is what nobody needs twice.
 */
enum class SettingsGroup {
    SOURCES,
    APPEARANCE,
    READING,
    DOWNLOADS,
    LANGUAGE,
    PRIVACY,
    ABOUT,
    ;

    val titleRes: Int
        get() = when (this) {
            SOURCES -> R.string.settings_sources
            APPEARANCE -> R.string.settings_appearance
            READING -> R.string.settings_reading
            DOWNLOADS -> R.string.settings_downloads
            LANGUAGE -> R.string.settings_language
            PRIVACY -> R.string.settings_privacy
            ABOUT -> R.string.settings_about
        }

    /** What a group that cannot be entered yet says instead of opening onto nothing. */
    val pendingRes: Int
        get() = when (this) {
            SOURCES -> R.string.settings_sources_pending
            DOWNLOADS -> R.string.settings_downloads_pending
            LANGUAGE -> R.string.settings_language_pending
            else -> R.string.settings_pending
        }

    val icon: ImageVector
        get() = when (this) {
            SOURCES -> Icons.Filled.Folder
            APPEARANCE -> Icons.Filled.Palette
            READING -> Icons.Filled.Book
            DOWNLOADS -> Icons.Filled.Download
            LANGUAGE -> Icons.Filled.Language
            PRIVACY -> Icons.Filled.Lock
            ABOUT -> Icons.Filled.Info
        }

    /**
     * The group's current value, in one line.
     *
     * `settings-and-about`: each summary row "states its current value, so a setting can
     * be checked without entering the group". A group with nothing to state yet says
     * what it will hold — which is a value too, and a more honest one than silence.
     */
    @Composable
    fun summary(settings: AppSettings): String = when (this) {
        APPEARANCE -> stringResource(settings.appearance.labelRes)
        READING -> stringResource(
            if (settings.turnPagesWithVolumeButtons) {
                R.string.settings_reading_summary_volume
            } else {
                R.string.settings_reading_summary
            },
        )
        LANGUAGE -> settings.language ?: stringResource(R.string.settings_language_system)
        PRIVACY -> stringResource(R.string.settings_privacy_summary)
        ABOUT -> stringResource(R.string.settings_about_summary)
        SOURCES, DOWNLOADS -> stringResource(pendingRes)
    }
}

/**
 * A whole row that responds to a tap, announced as a button.
 *
 * `Modifier.clickable` alone leaves a screen reader to guess what the row is; the role
 * is what makes it announce as one thing rather than as a heading beside a subtitle.
 */
@Composable
internal fun Modifier.clickableRow(onClick: () -> Unit): Modifier =
    clickable(role = Role.Button, onClick = onClick)
