package app.storyarc.core.playback

import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * The one session in the app's process, and the one thing every surface observes.
 *
 * An `object`, because a process-wide singleton is the only lifetime longer than every
 * screen, and because `audio-playback` allows exactly one session: "two books speaking at
 * once is never what was meant". `ReadAloudHost` is the same shape for the same reason, and
 * this is where the two will meet — read-aloud has its own engine and its own host today,
 * and the seam that lets it become a second [PlayerSource] is [start].
 *
 * **What it owns and what it does not.** It owns the connection to [PlaybackService] and
 * the [PlaybackCentre] that drives whatever is playing. It does not own the audio: the
 * service does, which is what lets a book carry on when the app's process is trimmed to
 * the service alone.
 */
object PlaybackHost {

    private val _nowPlaying = MutableStateFlow<NowPlaying?>(null)

    /** What every playback surface draws, or null when nothing is playing. */
    val nowPlaying: StateFlow<NowPlaying?> = _nowPlaying.asStateFlow()

    /**
     * Where a position goes when a session gives it up.
     *
     * Set by the app once, at start-up. A lambda rather than a `ProgressStore`, because
     * `:core:playback` decodes audio and has no business knowing that a library keeps a
     * database — and because the same hook is what will let read-aloud's own writer stay
     * where it is.
     */
    var recordPosition: ((publicationId: String, position: PlaybackPosition, parts: List<PlaybackPart>) -> Unit)? = null

    private val centre = PlaybackCentre(
        record = { source, position ->
            recordPosition?.invoke(source.publicationId, position, source.parts)
        },
    ).apply {
        onChange = { playing ->
            _nowPlaying.value = playing
            if (playing == null) {
                // The book ran out, or was displaced. Nothing to put back, so the carousel
                // and a car both stop offering it.
                memory?.forget()
                PlaybackService.resumption = null
            } else {
                // Where the audio has reached, kept where a service the system starts on
                // its own can read it. See [PlaybackMemory] — a field alone was null in
                // exactly the case resumption exists for.
                memory?.moveTo(playing.publicationId, playing.partIndex, playing.offsetMillis)
            }
        }
    }

    /** The id of the publication being played, or null. Feeds `SessionHandover.opening`. */
    val playingId: String? get() = centre.playingId

    private var controller: MediaController? = null
    private var current: AudiobookSource? = null
    private var memory: PlaybackMemory? = null
    private var skips: SkipPreferences? = null

    private val _skipIntervals = MutableStateFlow(SkipIntervals.DEFAULT)

    private val _sleep = MutableStateFlow<SleepTimer?>(null)

    /** The sleep timer counting down, or null when none is set. */
    val sleep: StateFlow<SleepTimer?> = _sleep.asStateFlow()

    /**
     * A scope as long as the process, because that is how long the audio lasts.
     *
     * The fade is the reason there is a scope here at all: it has to keep running while the
     * listener is asleep with the screen off, and nothing tied to a screen does.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var countdown: Job? = null

    /**
     * Plays a narrated audiobook, displacing whatever was playing.
     *
     * The controller is built on the first call and kept: connecting is asynchronous — it
     * binds to a service — and doing it per book would put a bind between the listener's
     * press and the first sound.
     */
    fun start(
        context: Context,
        book: Audiobook,
        from: PlaybackPosition? = null,
        speed: PlaybackSpeed = PlaybackSpeed.NORMAL,
        chapterWord: String = "Chapter",
    ) {
        memory = PlaybackMemory.open(context).also {
            it.remember(book, from?.partIndex ?: 0, from?.offsetMillis ?: 0)
        }
        // Read before the first sound, so the first press of a skip control moves by what
        // the listener chose rather than by the default and then by their choice.
        skips = SkipPreferences.open(context).also {
            val intervals = it.intervals()
            _skipIntervals.value = intervals
            centre.skipIntervals = intervals
        }
        withController(context) { player ->
            val source = AudiobookSource(book, player, chapterWord)
            current = source
            source.prepare(from)
            // Before the first sound rather than after it. A speed applied once the audio
            // is running is a sentence the listener hears at the wrong pace, and it is the
            // one they were about to be told is the start of a chapter.
            source.setSpeed(speed)
            centre.start(source)
            PlaybackService.resumption = PlaybackService.Resumption(
                items = book.sources.map { androidx.media3.common.MediaItem.fromUri(it.uri) },
                startIndex = from?.partIndex ?: 0,
                startPositionMs = from?.offsetMillis ?: 0L,
            )
        }
    }

    /** Pause and play, from wherever the listener reached for it. */
    fun toggle() = centre.toggle()

    /**
     * Sets, replaces or clears the sleep timer.
     *
     * @param after what the listener chose, or null to turn it off. A choice this session
     *   cannot honour — *end of chapter* where nothing knows how long the chapter is —
     *   leaves no timer set, because `audio-playback` requires a control that cannot work to
     *   be absent rather than present and refusing.
     */
    fun setSleepTimer(after: SleepAfter?) {
        countdown?.cancel()
        val timer = after?.let { SleepTimer.of(it, _nowPlaying.value) }
        _sleep.value = timer
        // Full volume again, whether the listener cleared a timer or replaced one part way
        // through its fade.
        controller?.volume = 1f
        if (timer == null) return

        countdown = scope.launch {
            while (isActive) {
                delay(TICK_MILLIS)
                val playing = _nowPlaying.value
                // A paused book is not falling asleep. The count holds where it is, which is
                // what a listener who paused to answer the door means by it.
                if (playing?.isPlaying != true) continue
                val next = (_sleep.value ?: return@launch).ticked(TICK_MILLIS, playing)
                _sleep.value = next
                controller?.volume = next.gain
                if (next.hasElapsed) {
                    fellAsleep()
                    return@launch
                }
            }
        }
    }

    /**
     * What the end of the timer does.
     *
     * `audio-playback`: "the position at which it stopped is recorded, so resuming starts a
     * little before it rather than where the fade ended". The rewind is the fade's own
     * length — the stretch the listener stopped taking in — so they start again at the last
     * thing they properly heard.
     *
     * Recorded here rather than left to the next write, because the next write is a tick
     * that only happens while something is playing, and nothing is.
     */
    private fun fellAsleep() {
        val playing = _nowPlaying.value
        val rewound = playing?.let {
            PlaybackPosition(
                partIndex = it.partIndex,
                offsetMillis = (it.offsetMillis - SleepTimer.FADE_MILLIS).coerceAtLeast(0),
            )
        }
        rewound?.let(centre::seek)
        if (playing?.isPlaying == true) centre.toggle()
        controller?.volume = 1f
        _sleep.value = null
        val source = current ?: return
        rewound?.let { recordPosition?.invoke(source.publicationId, it, source.parts) }
    }

    /** Ends the session: the listener closed it, or the book ran out of audio. */
    fun stop() {
        setSleepTimer(null)
        centre.stop()
        current = null
    }

    fun seek(to: PlaybackPosition) = centre.seek(to)

    fun setSpeed(speed: PlaybackSpeed) = centre.setSpeed(speed)

    /** Moves to the start of a part, whichever way this publication's parts are laid out. */
    fun seekToPart(index: Int) {
        current?.seekToPart(index)
    }

    /**
     * Skips by the listener's own interval, which is a product decision and not media3's.
     *
     * **This used to do the arithmetic here, and it was wrong in two ways.** It added the
     * interval to the offset and clamped at zero, and a comment said the boundary case was
     * free: "for a single file that is free … for a folder media3 carries the seek into the
     * next item itself". media3 does not — `BasePlayer.seekToOffset` clamps to the current
     * item at both ends. So skipping back five seconds into chapter two landed at the start
     * of chapter two, which is the stop `audio-playback` forbids by name. Both halves are
     * now [PlaybackCentre.skip]'s, over [PlaybackTimeline].
     */
    fun skip(direction: SkipDirection) = centre.skip(direction)

    /** How far a skip moves, for a control that has to state its own interval. */
    val skipIntervals: StateFlow<SkipIntervals> = _skipIntervals.asStateFlow()

    /**
     * Changes how far a skip moves, and remembers it.
     *
     * `audio-playback` asks for an interval "the listener can configure". Written as it is
     * chosen rather than when the book ends, for [setSpeed]'s reason: a listener who adjusts
     * it and then loses the process would otherwise be asked the same question again.
     *
     * **The notification is told rather than left to notice.** Its two outer buttons carry
     * the interval in their glyph and their label, and those are set when a controller
     * connects — so a change made while the shade is showing the old number needs a nudge,
     * and [PlaybackService.COMMAND_REFRESH_BUTTONS] is it.
     */
    fun setSkipIntervals(intervals: SkipIntervals) {
        _skipIntervals.value = intervals
        centre.skipIntervals = intervals
        skips?.remember(intervals)
        val refresh = SessionCommand(PlaybackService.COMMAND_REFRESH_BUTTONS, Bundle.EMPTY)
        controller?.takeIf { it.isSessionCommandAvailable(refresh) }
            ?.sendCustomCommand(refresh, Bundle.EMPTY)
    }

    /**
     * How often the countdown looks at the clock.
     *
     * Short enough that the fade is a fade rather than a staircase — half a second of a
     * thirty-second ramp is a step of about two per cent — and long enough that a sleeping
     * phone is not woken sixty times a second.
     */
    private const val TICK_MILLIS = 500L

    private fun withController(context: Context, body: (MediaController) -> Unit) {
        controller?.let { body(it); return }
        val token = SessionToken(
            context.applicationContext,
            ComponentName(context.applicationContext, PlaybackService::class.java),
        )
        val future = MediaController.Builder(context.applicationContext, token).buildAsync()
        future.addListener(
            {
                val built = runCatching { future.get() }.getOrNull() ?: return@addListener
                controller = built
                body(built)
            },
            // The main thread, because everything a `Player` is asked below has to be.
            MoreExecutors.directExecutor(),
        )
    }
}
