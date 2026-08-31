package app.storyarc.feature.settings

import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.AppSettings

/**
 * What the reader has asked of the queue, and what it has spent.
 *
 * This group used to be the whole downloads feature: the policy, the queue, every file on
 * the device and the only way to remove one — inside Settings, behind a list of groups.
 * `offline-downloads` now makes *everything on this device* one of the app's three
 * destinations, so the files, the queue and removal left for the Downloads destination,
 * which is where a reader looks for them and where they are one tap away. iOS's
 * `DownloadsSettings` was cut back to the same three choices at the same time.
 *
 * What stays is what is genuinely a setting: whether to wait for Wi-Fi, how much disk to
 * spend, whether a finished publication keeps its download — three choices that change what
 * the queue *does* rather than what is in it — and the total, because a reader standing in
 * the storage screen is asking how much room this app takes and deserves the number without
 * being sent somewhere else for it.
 */
@Composable
internal fun DownloadsGroup(
    /**
     * What the files actually weigh. Asked of the filesystem by the caller, because the
     * system can reclaim a download and a total that counts bytes nobody has is the kind of
     * number that makes a reader distrust the whole screen.
     */
    bytesOnDisk: Long,
    /** The reader's own policy for the queue, and how to change it. */
    settings: AppSettings = AppSettings.Defaults,
    onChange: (AppSettings) -> Unit = {},
    /** The row a search result pointed at, if the reader arrived through one. */
    highlight: SettingsAnchor? = null,
) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current

    Policy(settings, onChange, highlight)

    Row(
        modifier = Modifier.fillMaxWidth().padding(top = StoryArcSpace.md),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = stringResource(R.string.downloads_total),
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textPrimary,
        )
        Text(
            text = Formatter.formatShortFileSize(context, bytesOnDisk),
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textSecondary,
        )
    }

    // Said rather than implied. A reader who came here looking for their files has to be
    // told where they went, or the move is a feature that vanished.
    Text(
        text = stringResource(R.string.downloads_manage_in_destination),
        style = MaterialTheme.typography.bodyMedium,
        color = palette.textSecondary,
    )
}

/**
 * What the reader has asked of the queue.
 *
 * The three `offline-downloads` calls policy: whether to wait for Wi-Fi, how much disk to
 * spend, and whether a finished publication keeps its download. All three change what the
 * queue does rather than what is in it, which is why they are what stayed behind when the
 * files left for their own destination.
 */
@Composable
private fun Policy(
    settings: AppSettings,
    onChange: (AppSettings) -> Unit,
    highlight: SettingsAnchor?,
) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current

    SettingsSwitchRow(
        title = stringResource(R.string.downloads_wifi_only),
        note = stringResource(R.string.downloads_wifi_only_note),
        checked = settings.downloadOverWifiOnly,
        onChange = { onChange(settings.copy(downloadOverWifiOnly = it)) },
        modifier = Modifier.settingsHighlight(SettingsAnchor.DOWNLOADS_WIFI_ONLY, highlight),
    )

    SettingsSwitchRow(
        title = stringResource(R.string.downloads_remove_after),
        note = stringResource(R.string.downloads_remove_after_note),
        checked = settings.removeDownloadsAfterFinishing,
        onChange = { onChange(settings.copy(removeDownloadsAfterFinishing = it)) },
        modifier = Modifier.settingsHighlight(
            SettingsAnchor.DOWNLOADS_REMOVE_AFTER_FINISHING,
            highlight,
        ),
    )

    // A short ladder rather than a free number: a reader knows "about two gigabytes", not
    // 2_147_483_648, and a text field for a byte count is a way to mistype one.
    Column(
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        modifier = Modifier
            .padding(top = StoryArcSpace.sm)
            .settingsHighlight(SettingsAnchor.DOWNLOADS_LIMIT, highlight),
    ) {
        Text(
            text = stringResource(R.string.downloads_limit),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textPrimary,
        )
        // Wrapping rather than one line, for the reason `LibraryControls` and
        // `ListOrderChips` wrap: at `font_scale 2.0` in a 320 dp window four chips do not
        // fit across, and a plain `Row` does not fail by scrolling — it fails by placing
        // the last chips past the edge, where no interaction reaches them at all. The
        // ladder is exactly where that hurts most: the chip past the edge is a limit the
        // reader can no longer choose.
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        ) {
            LIMITS.forEach { limit ->
                FilterChip(
                    selected = settings.maximumDownloadBytes == limit,
                    onClick = { onChange(settings.copy(maximumDownloadBytes = limit)) },
                    label = {
                        Text(
                            text = limit?.let { Formatter.formatShortFileSize(context, it) }
                                ?: stringResource(R.string.downloads_limit_none),
                        )
                    },
                )
            }
        }
    }
}

/**
 * Null is "no limit", and it comes first because it is the default.
 *
 * Round decimal values rather than powers of two: the platform formats a size in decimal
 * gigabytes, so 2^30 renders as "1.1 GB" and a ladder of those reads like a mistake.
 */
private val LIMITS = listOf<Long?>(null, 1_000_000_000, 5_000_000_000, 20_000_000_000)
