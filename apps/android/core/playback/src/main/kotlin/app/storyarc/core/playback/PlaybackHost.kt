package app.storyarc.core.playback

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import androidx.media3.session.MediaController
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
 * once is never what was meant". `ReadAloudHost` is the same shape for the same reason.
 *
 * **Where the two meet is [SpokenAudio], and it is not here.** Read-aloud still has its own
 * engine and its own host — becoming a second [PlayerSource] is task 6.1 — so until then the
 * two sessions are arbitrated rather than merged: both hosts are [SpokenAudio.Speaker]s, and
 * [start] asks that one authority whether it may make a sound. iOS needs no such object
 * because its voice is already a source of the single `PlayerCentre`; the guarantee is the
 * same on both, the shape is each platform's.
 *
 * **What it owns and what it does not.** It owns the connection to [PlaybackService] and
 * the [PlaybackCentre] that drives whatever is playing. It does not own the audio: the
 * service does, which is what lets a book carry on when the app's process is trimmed to
 * the service alone.
 */
object PlaybackHost : SpokenAudio.Speaker {

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

    /**
     * Internal rather than private so a test can start a source in this object.
     *
     * [start] needs a bound `MediaController` before it holds anything, so every delegation
     * below was reachable by no test at all: a verifier replaced [refresh] with `= Unit` on
     * 2026-09-08 and both `:core:playback` and `:app` reported BUILD SUCCESSFUL, which is
     * the tick silently stopping. `RemainingChapterTimeTest` now drives [refresh] through
     * here. Nothing outside this module can see it, and nothing inside it may use it to
     * bypass the host.
     */
    internal val centre = PlaybackCentre(
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

    /**
     * The publication being narrated — its id and title — or null. This host's half of what
     * [SpokenAudio] answers for both; the title is what a displacement notice would name,
     * and for a narrator it never does.
     */
    override val speaking: SpokenAudio.Spoken? get() = centre.playing

    /** A narrated file. Displacing one owes the listener nothing — see [VoiceStoppedNotice]. */
    override val kind: SpokenAudio.Kind = SpokenAudio.Kind.NARRATOR

    /**
     * Ends the narrated session because something else is about to speak.
     *
     * [stop] rather than a teardown of its own, deliberately: a session displaced by a voice
     * and a session the listener closed are the same ending, and giving the first a shorter
     * one is how a sleep timer outlives the book it was counting down.
     */
    override fun endSpeaking() = stop()

    init {
        // From the initialiser, which runs on the first access to this object — and starting
        // a book *is* an access, so a host that has not registered has never played.
        SpokenAudio.shared.register(this)
    }

    private var controller: MediaController? = null
    private var current: AudiobookSource? = null
    private var memory: PlaybackMemory? = null

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
     * Plays a narrated audiobook, displacing whatever was speaking — of either kind.
     *
     * The controller is built on the first call and kept: connecting is asynchronous — it
     * binds to a service — and doing it per book would put a bind between the listener's
     * press and the first sound.
     *
     * **The first line is the seam.** [PlaybackCentre.start] displaces what *it* holds,
     * which is only ever a narrated file; asking [SpokenAudio] instead reaches the voice as
     * well, so tapping an audiobook while an EPUB is being read aloud stops the voice and
     * writes where it reached, rather than adding a second thing to listen to. It also
     * answers the question iOS's `listen` asks and this did not: tapping the cover of the
     * book already playing keeps the session instead of restarting the audio, which
     * `audio-playback` requires by name — "opening it never restarts, reloads or
     * repositions the audio".
     */
    fun start(
        context: Context,
        book: Audiobook,
        from: PlaybackPosition? = null,
        speed: PlaybackSpeed = PlaybackSpeed.NORMAL,
        chapterWord: String = "Chapter",
    ) {
        if (SpokenAudio.shared.claim(book.id, by = this) == SessionHandover.ADOPT) return

        memory = PlaybackMemory.open(context).also {
            it.remember(book, from?.partIndex ?: 0, from?.offsetMillis ?: 0)
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

    /**
     * Writes the audiobooks on the device where a car can read them.
     *
     * `audio-playback` asks a car surface to list them, and the system starts [PlaybackService]
     * for that question without starting the app. The service therefore cannot ask a library
     * that lives in the app; the app must have written the answer down first. Call this
     * whenever the library changes — a scan, a download, a deletion — and pass every audiobook
     * each time, because the file is replaced rather than added to.
     *
     * The rows are stale between calls. That is the trade `design.md` records: a car one
     * download behind still plays every book it names, and the alternative is a car that
     * offers nothing.
     */
    fun publishCarLibrary(context: Context, books: List<CarBook>) {
        CarLibrary.open(context).publish(books)
    }

    /** Pause and play, from wherever the listener reached for it. */
    fun toggle() = centre.toggle()

    /**
     * Gives the system's own controls the picture the player draws.
     *
     * `audio-playback`: the shade and the lock screen are "given that same artwork rather than
     * a second one". The picture is the app's — this module has no design system to draw a
     * coverless well with — so it arrives here as a file the session can load, once the player
     * has drawn it. Named for a publication so that a picture arriving after the book it was
     * drawn for has ended is dropped rather than put on the next one.
     */
    fun setArtwork(publicationId: String, artwork: Uri) {
        current?.takeIf { it.publicationId == publicationId }?.setArtwork(artwork)
    }

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

    /**
     * Writes where the audio has reached, read from the player at this moment.
     *
     * The app calls this at the moments a listener expects to be remembered and the session
     * itself cannot see: the activity leaving the foreground, a scrub settling, and the
     * periodic floor. The pause and the skip are [PlaybackCentre]'s own — see
     * [PlaybackCentre.recordReached] for why the read must reach the player.
     */
    fun recordReached() = centre.recordReached()

    /**
     * Republishes where the audio has reached, so a stated remainder moves with it.
     *
     * The app calls this on the same tick it writes a position on. See
     * [PlaybackCentre.refresh] for why a playing file publishes nothing by itself.
     */
    fun refresh() = centre.refresh()

    /** Moves to the start of a part, whichever way this publication's parts are laid out. */
    fun seekToPart(index: Int) {
        current?.seekToPart(index)
        // A chapter chosen from a list is a place the listener picked, not one the audio
        // drifted to.
        centre.recordReached()
    }

    /**
     * Skips by the fixed interval, which is a product decision and not media3's.
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
