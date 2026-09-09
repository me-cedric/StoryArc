package app.storyarc

import android.graphics.Bitmap
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
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.storyarc.core.designsystem.control.StoryArcSliderTrack
import app.storyarc.core.designsystem.format.clock
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.model.Publication
import app.storyarc.core.playback.NowPlaying
import app.storyarc.core.playback.PlaybackPosition
import app.storyarc.core.playback.PlaybackSpeed
import app.storyarc.core.playback.SkipDirection
import app.storyarc.core.playback.SkipIntervals
import app.storyarc.core.playback.SleepAfter
import app.storyarc.core.playback.SleepTimer
import app.storyarc.core.playback.SpokenAudio
import app.storyarc.core.playback.sentence
import kotlinx.coroutines.launch

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
 * **It takes a `Publication` too, now, and the sentence above still holds.** The publication
 * is nullable and starts nothing: it is where the cover and the format come from, and the
 * session goes on without it — see `PlayingBook.following` for when it is null. What is
 * drawn from it is [PlayerArtwork], the first thing in the column.
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
    onSkip: (SkipDirection) -> Unit,
    onSeek: (PlaybackPosition) -> Unit,
    /**
     * The drag ended, so the position the listener chose may be written down.
     *
     * Apart from [onSeek], which fires on every pixel of the drag: a scrub is a deliberate
     * jump and `audio-playback` asks for one to be recorded, and a store written sixty times
     * a second is a different defect. Required rather than defaulted, like every other verb
     * here: a screen that quietly wrote nothing is the defect this exists to remove.
     */
    onSeekSettled: () -> Unit,
    onChooseChapter: (Int) -> Unit,
    onSpeed: (PlaybackSpeed) -> Unit,
    sleep: SleepTimer?,
    onSleep: (SleepAfter?) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    /**
     * The authority that arms the word a displaced voice owes. The app's one, except in a test
     * — a parameter rather than a read of the singleton inside, so a test can arm it.
     */
    spokenAudio: SpokenAudio = SpokenAudio.shared,
    /**
     * The publication being played as the library knows it, for the cover and the format —
     * or null when nothing in the app started it, which is what a book the system resumed
     * after the process died looks like. See `PlayingBook.following`.
     */
    publication: Publication? = null,
    /** Where a cover comes from. `OnDeviceCover` takes its cover the same way, for a test's sake. */
    cover: suspend (Publication, Int) -> Bitmap? = { _, _ -> null },
    /** Where the drawn artwork goes for the system's own controls, or null where nothing wants it. */
    onArtwork: ((Bitmap) -> Unit)? = null,
) {
    val palette = LocalStoryArcPalette.current
    // `ebook-reader`, *Opening a different publication*: an audiobook opened while a voice was
    // speaking lands here, so here is where the listener is told once that the voice stopped.
    val snackbars = remember { SnackbarHostState() }
    VoiceStoppedWord(spokenAudio, snackbars)
    // A `Scaffold` with a top bar, like every other screen a reader comes back from. It is
    // also what supplies the status-bar inset: the first draft was a bare `Column` and the
    // publication's title sat under the clock, which a screenshot caught and no unit test
    // would have.
    Scaffold(
        modifier = modifier,
        containerColor = palette.surfaceCanvas,
        snackbarHost = { SnackbarHost(snackbars) },
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
        // First, because `audio-playback` lists the cover first and because the artwork is
        // the interface: the transport reads as belonging to the picture above it. Bounded at
        // 320 dp so the transport stays on a phone's screen at the largest text size — the
        // chapter list below is what scrolls away, never a control.
        PlayerArtwork(
            title = playing.title,
            publication = publication,
            cover = cover,
            onArtwork = onArtwork,
        )

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

        Position(playing, onSeek, onSeekSettled)
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
            // Only the chapter being played has a remainder to state. `audio-playback` asks
            // for it on "the chapter in progress", and a chapter nobody has reached has all
            // of itself left, which is what its duration already says.
            val left = playing.leftInPartMillis.takeIf { index == playing.partIndex }
            // The overload with `content` trailing. The one taking `headlineContent` first
            // is deprecated at material3 1.5.0-alpha26 and `allWarningsAsErrors` says so.
            ListItem(
                modifier = Modifier.clickable { onChooseChapter(index) },
                // The duration and the remainder in one line, so the merged row states one
                // value. `audio-playback` asks a screen reader to hear "the chapter, its
                // duration, its mark and the remaining time as one control", and
                // `Modifier.clickable` above is what merges them.
                supportingContent = part.duration.statedMillis?.let { millis ->
                    {
                        Text(
                            text = left?.let {
                                stringResource(R.string.player_chapter_left, clock(millis), clock(it))
                            } ?: clock(millis),
                        )
                    }
                },
                trailingContent = chapterMark(index, playing.partIndex)?.let { mark ->
                    { Text(stringResource(mark)) }
                },
                content = { Text(part.title) },
            )
        }
    }
    }
}

/**
 * The word beside a chapter in the player's list, or none.
 *
 * `audio-playback`: "a chapter already finished is marked as finished, a chapter not yet
 * reached carries no mark, and the chapter in progress is marked as the one in progress".
 * One position marks every row, because a listener is in one place at a time.
 *
 * The player's own words rather than the library's read-state pair, which the publication
 * page uses: those read *Gelesen* and *Terminado* in two of the four languages, and a
 * chapter of an audiobook was heard rather than read.
 */
private fun chapterMark(index: Int, partIndex: Int): Int? = when {
    index < partIndex -> R.string.player_chapter_finished
    index == partIndex -> R.string.player_current_chapter
    else -> null
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
private fun Position(
    playing: NowPlaying,
    onSeek: (PlaybackPosition) -> Unit,
    onSeekSettled: () -> Unit,
) {
    val total = playing.statedPartDurationMillis
    // **The offset inside the chapter, not the seek target.** The rail is ranged over one
    // chapter, and for a single chaptered file `offsetMillis` is a time into the whole file:
    // a handle fed one and ranged over the other sits pinned at its own end from the second
    // chapter on. `NowPlaying.positionInPart` is the way back to what a seek takes.
    val offset = playing.offsetInPartMillis
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (playing.isScrubbable && total != null) {
            Slider(
                value = offset.toFloat(),
                onValueChange = {
                    onSeek(playing.positionInPart(it.toLong()))
                },
                onValueChangeFinished = onSeekSettled,
                valueRange = 0f..total.toFloat(),
                // The handle stands on the rail. See `StoryArcSliderTrack`: at the start of
                // a chapter there is no active half to hold Material's gap open.
                track = { state -> StoryArcSliderTrack(state) },
                modifier = Modifier.semantics {
                    contentDescription = "" // named by the row below it
                    // **In time, not as a percentage.** `audio-playback`: the scrub is
                    // "announced as an adjustable with its position stated in time, not as
                    // a percentage". A `Slider`'s own state description is a percentage,
                    // and this is what replaces it.
                    stateDescription = "${clock(offset)} of ${clock(total)}"
                },
            )
        } else {
            // No total, so no line to drag along. A flat indeterminate line would claim a
            // progress this source cannot report.
            Spacer(Modifier.height(4.dp))
        }

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                text = clock(offset),
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
 * **The interval is stated on the control itself**, which `audio-playback` asks for by
 * name. The number here is read from [SkipIntervals], so the control states the distance
 * the audio actually moves. The two numbers are a **product decision**: media3's own are
 * 5 s and 15 s, and both are wrong for spoken word in the same direction.
 */
@Composable
private fun Transport(
    isPlaying: Boolean,
    onToggle: () -> Unit,
    onSkip: (SkipDirection) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Skip(
            icon = Icons.Filled.Replay,
            seconds = SkipIntervals.BACK_SECONDS,
            label = pluralStringResource(
                R.plurals.player_skip_back,
                SkipIntervals.BACK_SECONDS,
                SkipIntervals.BACK_SECONDS,
            ),
            onClick = { onSkip(SkipDirection.BACK) },
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
            seconds = SkipIntervals.FORWARD_SECONDS,
            label = pluralStringResource(
                R.plurals.player_skip_forward,
                SkipIntervals.FORWARD_SECONDS,
                SkipIntervals.FORWARD_SECONDS,
            ),
            onClick = { onSkip(SkipDirection.FORWARD) },
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
 * So a plain arrow with the number beside it. It states the right interval, and it grows
 * with the reader's text size. A glyph does not grow.
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
            track = { state -> StoryArcSliderTrack(state) },
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

/**
 * Shows the word a displaced voice owes, once, as a snackbar — and takes it by showing it.
 *
 * **Told once is the take.** [SpokenAudio.takeVoiceStopped] spends the notice the moment this
 * screen reads it, so a second composition — the same player redrawn, or a return to it — finds
 * nothing. A `Snackbar` because that is this codebase's word for a brief, non-modal notice that
 * leaves on its own; Material's host also marks it a polite live region, which is what has
 * TalkBack say the sentence once.
 *
 * **Collected with the lifecycle, and that is load-bearing.** Two screens can be composed at
 * the same moment a voice is displaced — the EPUB activity behind, this player in front — and
 * only the one the listener is looking at may take the word. `collectAsStateWithLifecycle`
 * stops collecting below `STARTED`, so a stopped activity never sees the notice pending.
 *
 * The snackbar is shown from a scope of its own rather than inside the effect: taking the
 * notice changes the collected value, which would restart an effect keyed on it and cancel the
 * very snackbar it had just begun to show.
 *
 * `EpubReaderOverlays.kt` carries the same effect over the page, because a feature module and
 * the app module cannot share a composable without one depending on the other; the rule behind
 * both is `VoiceStoppedNotice`, in `:core:playback`, and asserted there.
 */
@Composable
private fun VoiceStoppedWord(spokenAudio: SpokenAudio, snackbars: SnackbarHostState) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val owed by spokenAudio.voiceStopped.collectAsStateWithLifecycle()
    LaunchedEffect(owed) {
        if (!owed.isPending) return@LaunchedEffect
        val sentence = spokenAudio.takeVoiceStopped().sentence(context) ?: return@LaunchedEffect
        // Long rather than Material's default. The surface this lands on is still being built
        // when the word starts — an EPUB is parsed after its overlay composes, a player draws
        // its transport a beat after it opens — and a Short snackbar was gone before the first
        // page drew: photographed on 2026-09-06 as a page with no word on it, twice.
        scope.launch { snackbars.showSnackbar(sentence, duration = SnackbarDuration.Long) }
    }
}

