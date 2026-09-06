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
import app.storyarc.core.model.DownloadHold
import app.storyarc.core.model.DownloadLibrary

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
    /**
     * What is on the device and what is still on its way.
     *
     * Handed in for the reason [bytesOnDisk] is: the downloads belong to the library that
     * fetched them. The records are also the whole of what this group needs to say why the
     * queue is waiting -- [DownloadLibrary.hold] reads them, so no queue has to be alive.
     */
    downloads: DownloadLibrary = DownloadLibrary(),
    /** The reader's own policy for the queue, and how to change it. */
    settings: AppSettings = AppSettings.Defaults,
    onChange: (AppSettings) -> Unit = {},
    /** The row a search result pointed at, if the reader arrived through one. */
    highlight: SettingsAnchor? = null,
) {
    val palette = LocalStoryArcPalette.current
    val context = LocalContext.current

    Waiting(downloads.hold(settings.maximumDownloadBytes))
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
 * Why the queue is waiting, and what ends the wait.
 *
 * `offline-downloads` requires a held queue to say what it is waiting for, and until now
 * nothing on either platform drew [DownloadLibrary.hold] at all: a reader whose queue was
 * waiting saw a list that had simply stopped.
 *
 * **The remedy is said, not only the state.** "Waiting for Wi-Fi" is a fact; what a reader
 * needs from it is that nothing is asked of them, because the queue starts again by itself. The
 * two cases where it does say so, and the one where it does not names the two things that would
 * end it.
 *
 * Nothing is drawn when the queue is not held -- an empty explanation of an absent problem is
 * the noise this row exists to avoid. iOS's `DownloadsSettings` draws the same two sentences.
 */
@Composable
private fun Waiting(hold: DownloadHold?) {
    if (hold == null) return
    val palette = LocalStoryArcPalette.current

    Column(
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
        modifier = Modifier.padding(bottom = StoryArcSpace.sm),
    ) {
        // The pause reason's own sentence, already translated and already drawn on the row of
        // every held download -- `DownloadsParts.kt`, and `DownloadQueueSection.swift` on iOS.
        // Said once here rather than written a second time, so the screen and the queue cannot
        // disagree in one language.
        Text(
            text = stringResource(hold.state),
            style = MaterialTheme.typography.bodyLarge,
            color = palette.textPrimary,
        )
        Text(
            text = stringResource(hold.remedy),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.textSecondary,
        )
    }
}

/**
 * What the queue is waiting for.
 *
 * Two of the three reuse the sentence the pause reason already carries, because they are the
 * same fact told to the same reader. The third has no pause reason: the reader's own maximum
 * stops the queue without marking a row, so it needs a sentence of its own.
 */
private val DownloadHold.state: Int
    get() = when (this) {
        DownloadHold.OUT_OF_SPACE -> R.string.downloads_paused_out_of_space
        DownloadHold.WAITING_FOR_WIFI -> R.string.downloads_paused_waiting_for_wifi
        DownloadHold.STORAGE_FULL -> R.string.downloads_held_storage_full
    }

/**
 * What ends the wait.
 *
 * Two of them end by themselves, and saying so is the point: a reader told only that the queue
 * is waiting is a reader looking for a button that should not exist. The third is the reader's
 * own choice, so it names both ways out -- and names them without ruling out the offer to free
 * room that `offline-downloads` asks for and this screen does not make.
 */
private val DownloadHold.remedy: Int
    get() = when (this) {
        DownloadHold.OUT_OF_SPACE -> R.string.downloads_held_out_of_space_note
        DownloadHold.WAITING_FOR_WIFI -> R.string.downloads_held_waiting_for_wifi_note
        DownloadHold.STORAGE_FULL -> R.string.downloads_held_storage_full_note
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
        // `ListOrderChips` wrap: at `font_scale 2.0` the four chips do not fit across the
        // 280 dp this group has in a 320 dp window. A plain `Row` does not fail by scrolling
        // and it does not place anything past the edge either -- it never measures a child
        // wider than the space still free. It fails by keeping the chips it can fit and
        // giving each of the rest whatever is left. Put a plain `Row` back and
        // `DownloadLimitWrapTest` measures the third chip at 25 dp by 228 dp in English,
        // 1 dp wide in German and no width at all in French; the fourth is never reached,
        // because the assertion on the third ends the test. A limit squeezed into a column
        // of single letters is one a reader cannot read, and a limit of no width is one no
        // interaction reaches at all. The ladder is where that hurts most: it is the whole
        // control.
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
 *
 * Visible to the module rather than to this file alone so `DownloadLimitWrapTest` asserts
 * against the ladder that is actually drawn, instead of a copy of it that can drift.
 */
internal val LIMITS = listOf<Long?>(null, 1_000_000_000, 5_000_000_000, 20_000_000_000)
