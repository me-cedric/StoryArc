package app.storyarc

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Redo
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.playback.NowPlaying
import app.storyarc.core.playback.PlaybackPosition
import app.storyarc.core.playback.PlaybackSpeed
import app.storyarc.core.playback.SleepAfter
import app.storyarc.core.playback.SleepTimer

/**
 * The full player: what is playing, where it is, and everything a listener of a book needs.
 *
 * `audio-playback`: it "shows the cover, the publication, the chapter, the position and
 * duration, and offers play, pause, skip back, skip forward, a scrub control, the chapter
 * list, playback speed and a sleep timer", and "the same source that fed the compact bar
 * feeds this, so opening it never restarts, reloads or repositions the audio".
 *
 * **That last clause is why this takes a [NowPlaying] and not a publication.** There is one
 * session, it is `PlaybackHost`'s, and this screen only draws it. A screen that took a
 * publication would have to start something to draw anything, which is precisely the
 * restart the spec forbids.
 *
 * **A scrolling column, and no fixed heights.** `audio-playback` at the largest text size:
 * "the surface scrolls if it must, and no transport control is pushed off the screen". The
 * transport is above the chapter list for the same reason — the list is what scrolls away.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun PlayerScreen(
    playing: NowPlaying,
    onToggle: () -> Unit,
    onSkip: (forward: Boolean) -> Unit,
    onSeek: (PlaybackPosition) -> Unit,
    onChooseChapter: (Int) -> Unit,
    onSpeed: (PlaybackSpeed) -> Unit,
    sleep: SleepTimer?,
    onSleep: (SleepAfter?) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    // A `Scaffold` with a top bar, like every other screen a reader comes back from. It is
    // also what supplies the status-bar inset: the first draft was a bare `Column` and the
    // publication's title sat under the clock, which a screenshot caught and no unit test
    // would have.
    Scaffold(
        modifier = modifier,
        containerColor = palette.surfaceCanvas,
        topBar = {
            TopAppBar(
                title = { Text(playing.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.player_back),
                            tint = palette.accent,
                        )
                    }
                },
            )
        },
    ) { insets ->
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(insets)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        playing.chapter?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // **How much could not be played, in the player's own controls** — never a dialog
        // and never an interruption. `publication-formats`: a damaged audiobook "plays what
        // it can and states how much it could not … rather than interrupting playback".
        if (playing.isPartial) {
            Text(
                text = pluralStringResource(
                    R.plurals.player_skipped_parts,
                    playing.skippedPartCount,
                    playing.skippedPartCount,
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Position(playing, onSeek)
        Transport(playing.isPlaying, onToggle, onSkip)
        Speed(playing.speed, onSpeed)
        Sleep(playing, sleep, onSleep)

        HorizontalDivider()

        Text(
            text = stringResource(R.string.player_chapters),
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        // `audio-playback`: "a publication with no chapter markers lists its parts in
        // playing order instead, rather than showing an empty list". There is nothing to
        // branch on here — a source's parts are never empty, which is the whole point of
        // `AudiobookChapters` giving an unchaptered book one part.
        playing.parts.forEachIndexed { index, part ->
            // The overload with `content` trailing. The one taking `headlineContent` first
            // is deprecated at material3 1.5.0-alpha26 and `allWarningsAsErrors` says so.
            ListItem(
                modifier = Modifier.clickable { onChooseChapter(index) },
                supportingContent = part.duration.statedMillis?.let { millis ->
                    { Text(clock(millis)) }
                },
                trailingContent = if (index == playing.partIndex) {
                    { Text(stringResource(R.string.player_current_chapter)) }
                } else {
                    null
                },
                content = { Text(part.title) },
            )
        }
    }
    }
}

/**
 * Where the audio is, and the scrub control — where there is one to offer.
 *
 * `audio-playback` offers the scrub "where a duration is known". A read-aloud session's
 * length is a guess from a character count that moves the moment the speed does, so
 * dragging against it would put the listener somewhere the handle did not say. What is
 * shown instead is the position without a total, which is the spec's own answer.
 */
@Composable
private fun Position(playing: NowPlaying, onSeek: (PlaybackPosition) -> Unit) {
    val total = playing.statedPartDurationMillis
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (playing.isScrubbable && total != null) {
            Slider(
                value = playing.offsetMillis.toFloat(),
                onValueChange = {
                    onSeek(PlaybackPosition(playing.partIndex, it.toLong()))
                },
                valueRange = 0f..total.toFloat(),
                modifier = Modifier.semantics {
                    contentDescription = "" // named by the row below it
                    // **In time, not as a percentage.** `audio-playback`: the scrub is
                    // "announced as an adjustable with its position stated in time, not as
                    // a percentage". A `Slider`'s own state description is a percentage,
                    // and this is what replaces it.
                    stateDescription = "${clock(playing.offsetMillis)} of ${clock(total)}"
                },
            )
        } else {
            // No total, so no line to drag along. A flat indeterminate line would claim a
            // progress this source cannot report.
            Spacer(Modifier.height(4.dp))
        }

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                text = clock(playing.offsetMillis),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            total?.let {
                Text(
                    text = clock(it),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // The whole publication, when every part states a length. Flat rather than wavy:
        // Material says a linear indicator "shouldn't be used in any elements smaller than
        // 40dp", and warns the wavy variant "may not be as visible" at small sizes.
        val elapsed = playing.elapsedTotalMillis
        val whole = playing.statedTotalMillis
        if (elapsed != null && whole != null && whole > 0) {
            LinearProgressIndicator(
                progress = { (elapsed.toFloat() / whole.toFloat()).coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth().clearAndSetSemantics { },
            )
        }
    }
}

/**
 * Skip back, play/pause, skip forward.
 *
 * **Fifteen and thirty, stated on the control itself.** `audio-playback`: "the audio moves
 * by a fixed interval … and the interval is stated on the control itself". The numbers are
 * a **product decision** — media3's own defaults are 5 s and 15 s, and both are wrong for
 * spoken word in the same direction.
 */
@Composable
private fun Transport(isPlaying: Boolean, onToggle: () -> Unit, onSkip: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Skip(
            icon = Icons.Filled.Replay,
            seconds = BACK_SECONDS,
            label = stringResource(R.string.player_skip_back),
            onClick = { onSkip(false) },
        )
        FilledIconButton(onClick = onToggle, modifier = Modifier.size(64.dp)) {
            Icon(
                imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                contentDescription = stringResource(
                    if (isPlaying) R.string.player_pause else R.string.player_play,
                ),
                modifier = Modifier.size(32.dp),
            )
        }
        Skip(
            icon = Icons.AutoMirrored.Filled.Redo,
            seconds = FORWARD_SECONDS,
            label = stringResource(R.string.player_skip_forward),
            onClick = { onSkip(true) },
        )
    }
}

/**
 * One skip control, with its interval **written under it**.
 *
 * `audio-playback`: "the interval is stated on the control itself". The obvious way to do
 * that is a numbered glyph, and Material's icon set cannot: it ships `Replay5`, `Replay10`
 * and `Replay30` and no `Replay15`. Fifteen seconds back is the design's **product
 * decision** and there is no Material icon for it, so leaning on a glyph would mean
 * drawing "10" on a control that moves fifteen.
 *
 * So a plain arrow with the number beside it. It states the right interval, it stays right
 * when the interval becomes configurable, and it grows with the reader's text size — which
 * a glyph does not.
 */
@Composable
private fun Skip(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    seconds: Int,
    label: String,
    onClick: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        // One element to a screen reader, named for what it does rather than read out as
        // an arrow and a loose number.
        modifier = Modifier.clearAndSetSemantics { contentDescription = label },
    ) {
        IconButton(onClick = onClick) {
            Icon(imageVector = icon, contentDescription = null, modifier = Modifier.size(32.dp))
        }
        Text(
            text = stringResource(R.string.player_seconds, seconds),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** 15 back and 30 forward. A **product decision** — see `PlaybackService`, which sets them. */
private const val BACK_SECONDS = 15
private const val FORWARD_SECONDS = 30

/**
 * How fast it runs, stated as a number.
 *
 * `audio-playback`: the value "is stated as a number", and "at least the range from half
 * speed to triple speed is offered". A slider over that range rather than a menu of
 * presets, because the range is continuous and a listener who wants 1.35× should not have
 * to accept 1.5×.
 */
@Composable
private fun Speed(speed: PlaybackSpeed, onSpeed: (PlaybackSpeed) -> Unit) {
    Column {
        Text(
            text = stringResource(R.string.player_speed, speed.label),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Slider(
            value = speed.rate.toFloat(),
            onValueChange = { onSpeed(PlaybackSpeed.of(it.toDouble())) },
            valueRange = PlaybackSpeed.SLOWEST.toFloat()..PlaybackSpeed.FASTEST.toFloat(),
            modifier = Modifier.semantics {
                // The value, not a percentage: a screen reader saying "62 per cent" of a
                // speed control tells a listener nothing they can act on.
                stateDescription = speed.label
            },
        )
    }
}

/**
 * When to stop, for a listener who is falling asleep.
 *
 * `audio-playback`: "a duration or *end of chapter* may be chosen, the remaining time is
 * shown on the player, and playback fades out rather than cutting off when it elapses".
 *
 * **End of chapter is offered only where there is one to stop at.** A session with no known
 * duration has no end of chapter, and the same requirement says every control the player
 * offers "works, or is absent — none is present and refusing" — so the option is missing
 * rather than inert. It is a **product decision** that a book player offers it at all;
 * `design.md` records that, and no guideline is cited for it.
 */
@Composable
private fun Sleep(playing: NowPlaying, timer: SleepTimer?, onSleep: (SleepAfter?) -> Unit) {
    val endOfChapter = playing.statedPartDurationMillis != null
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = timer
                ?.let { stringResource(R.string.player_sleep_in, clock(it.remainingMillis)) }
                ?: stringResource(R.string.player_sleep),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        // A row that wraps, because at the largest text size five durations and a chapter
        // do not fit across a phone and `audio-playback` asks that nothing be "pushed off
        // the screen".
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (timer != null) {
                FilterChip(
                    selected = false,
                    onClick = { onSleep(null) },
                    label = { Text(stringResource(R.string.player_sleep_off)) },
                )
            }
            for (minutes in SleepTimer.OFFERED_MINUTES) {
                val after = SleepAfter.Duration(minutes * 60_000L)
                FilterChip(
                    selected = timer?.after == after,
                    onClick = { onSleep(after) },
                    label = { Text(stringResource(R.string.player_sleep_minutes, minutes)) },
                )
            }
            if (endOfChapter) {
                FilterChip(
                    selected = timer?.after == SleepAfter.EndOfChapter,
                    onClick = { onSleep(SleepAfter.EndOfChapter) },
                    label = { Text(stringResource(R.string.player_sleep_end_of_chapter)) },
                )
            }
        }
    }
}

/**
 * The player, once the book has run out.
 *
 * `audio-playback` says the compact bar goes away at the end of a publication, and a
 * listener standing on the full player when that happens is left on a screen with nothing
 * to draw. What they get is a sentence and the way back — not a screen that navigates
 * itself, which would be a second answer to a question this app spent a rewrite reducing
 * to one.
 */
@Composable
internal fun PlayerFinishedScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = stringResource(R.string.player_nothing_playing),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        TextButton(onClick = onBack) { Text(stringResource(R.string.player_back)) }
    }
}

/** A duration as a listener reads one: `1:02:03`, or `2:03` under an hour. */
internal fun clock(millis: Long): String {
    val total = (millis / 1000).coerceAtLeast(0)
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val seconds = total % 60
    return if (hours > 0) {
        "%d:%02d:%02d".format(hours, minutes, seconds)
    } else {
        "%d:%02d".format(minutes, seconds)
    }
}
