package app.storyarc.core.playback

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import androidx.media3.common.Player
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
            wakeAtPartEnd(playing)
            // The session has gone, so whatever held it has. Here rather than in each of the
            // three endings, because `PlaybackCentre` routes all of them through one
            // teardown and this is where that teardown is heard.
            //
            // **The sleep timer goes with it**, and this is the only place that catches all
            // three endings: [stop] clears it for the listener's own stop, and a book that
            // ran out of audio — or a voice that ran out of words — reaches the centre as an
            // idle session instead, with no call of its own. A timer left counting on a book
            // that has already stopped fades a book that is not playing and then "wakes" to
            // stop it again.
            if (playing == null) {
                voice = null
                setSleepTimer(null)
            }
            rememberForResumption(playing)
        }
    }

    /**
     * Keeps the record a service the system restarts plays from, for a source media3 plays.
     *
     * **Only for one.** [memory] is null while the voice holds the session, and this returns
     * on that: a read-aloud session has nothing media3 could put back — there is no file, no
     * item and no time into one — so remembering it would replace a real audiobook's record
     * with one the resumption path cannot honour, and the shade's carousel would offer a
     * book that plays silence. The displaced audiobook's own record is written on its way
     * out, by the ending that displaced it.
     */
    private fun rememberForResumption(playing: NowPlaying?) {
        val memory = memory ?: return
        if (playing == null) {
            // The book ran out, or was displaced. Nothing to put back, so the carousel
            // and a car both stop offering it.
            memory.forget()
            PlaybackService.resumption = null
        } else {
            // Where the audio has reached, kept where a service the system starts on
            // its own can read it. See [PlaybackMemory] — a field alone was null in
            // exactly the case resumption exists for.
            //
            // The part's start plus the offset into it, because media3 resumes at a time
            // into an item and a position states a time into a part. The two are the same
            // number for a folder, and for a chaptered file they differ by the mark.
            memory.moveTo(
                publicationId = playing.publicationId,
                partIndex = playing.partIndex,
                offsetMillis = playing.itemTimeMillis,
            )
            // And the process-wide field, which [PlaybackService.onPlaybackResumption]
            // prefers over the file. Refreshed here rather than only at [start], so the
            // carousel resumes where the audio reached instead of where it began — and
            // so both answers come out of the one record that holds an item time.
            memory.last()?.let { PlaybackService.resumption = PlaybackResumption.of(it) }
        }
    }

    /**
     * The publication being narrated — its id and title — or null. This host's half of what
     * [SpokenAudio] answers for both; the title is what a displacement notice would name,
     * and for a narrator it never does.
     *
     * **Null while the voice holds the session, although the session is this centre's.**
     * One player with two sources means the voice's surface is built here, and it must not
     * mean the voice is answered for here: `VoiceStoppedNotice` asks *what kind* of speaker
     * was displaced, this host is the [SpokenAudio.Kind.NARRATOR], and a voice reported from
     * here would be silenced without the word it is owed. The voice's own host answers for
     * it, and [SpokenAudio.silence] passes over a speaker that reports nothing.
     */
    override val speaking: SpokenAudio.Spoken? get() = if (voice == null) centre.playing else null

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

    /**
     * The voice, while it is the source this centre holds. Null the rest of the time.
     *
     * Two questions are answered from it and nothing else is: whether [speaking] is this
     * host's to answer, and whether [stopVoice] is being asked to end a session the voice
     * still holds. Cleared by the one teardown, in the `onChange` above.
     */
    private var voice: PlayerSource? = null

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

    /** The republish that waits for the part playing to end. See [wakeAtPartEnd]. */
    private var partEnd: Job? = null

    /**
     * Republishes just after the part playing ends, so the crossing is written at that moment.
     *
     * A folder crosses with a media3 transition callback. A chapter mark inside one file
     * raises no callback, so [PlaybackCentre.publish] would see the crossing only at the next
     * fifteen-second tick. Every publish calls this again, so a pause, a seek or a new speed
     * replaces the wait that was set before it.
     */
    private fun wakeAtPartEnd(playing: NowPlaying?) {
        partEnd?.cancel()
        val wait = playing?.untilPartEndsMillis ?: return
        partEnd = scope.launch {
            delay(wait + PART_END_MARGIN_MILLIS)
            centre.refresh()
        }
    }

    /** How far past the mark the republish lands, so the player's clock is over it. */
    private const val PART_END_MARGIN_MILLIS = 250L

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

        // The offset here is the part's, and media3 wants the item's. For a chaptered single
        // file the two differ by a mark nothing has read yet, so this record is short by that
        // mark until the first report corrects it — see [onChange], which runs on the first
        // callback the player raises. A resumption inside that window starts the book at the
        // remembered part's own offset rather than at the mark, which is the honest floor for
        // a service that has to answer before any audio has been read.
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
     * Adopts a book the car started directly, as the app's one session.
     *
     * [PlaybackService.LibraryCallback.onSetMediaItems] is the one caller, from the same
     * process this object runs in — a car reaches no other. Before this, the car's choice
     * went straight to the service player with no [PlayerSource] attached at all: no
     * `reading-progress` write, no [PlaybackMemory] kept current, and the row the car itself
     * drew next always started at zero. [player] is the service's own decoder, the one the
     * car's own `setMediaItems`/`prepare`/`play` chain is about to load and start — see
     * [AudiobookSource.attach] for why this does not load it a second time.
     *
     * @param book what the service already resolved the car's choice to — [PlaybackMemory]'s
     *   own record, or a shelf row — so the position matches exactly what the car was handed.
     * @param partTime a shelf row's position, which states a time into a part rather than
     *   into the item. See [AudiobookSource.attach].
     */
    internal fun attachCarStart(
        context: Context,
        book: PlayedBook,
        player: Player,
        partTime: PlaybackPosition? = null,
    ) {
        val audiobook = Audiobook(
            id = book.id,
            title = book.title,
            author = book.author,
            sources = book.uris.mapIndexed { index, uri ->
                Audiobook.AudioPart(uri, book.partTitles.getOrNull(index).orEmpty())
            },
            artworkUri = book.artworkUri,
        )
        // The book already speaking is adopted rather than restarted, exactly as [start]'s
        // own first line answers the app's side of the same question.
        if (SpokenAudio.shared.claim(audiobook.id, by = this) == SessionHandover.ADOPT) return
        memory = PlaybackMemory.open(context).also {
            it.remember(audiobook, book.partIndex, book.offsetMillis)
        }
        val source = AudiobookSource(audiobook, player)
        current = source
        source.attach(from = partTime)
        centre.attach(source)
    }

    /**
     * Takes a voice that has already begun speaking as this centre's one session.
     *
     * `audio-playback`, *One player for everything that speaks*: "every source of spoken
     * audio — a narrated audiobook and the read-aloud voice alike — SHALL drive that one
     * surface". Until this existed the Android voice drove a surface of its own, so a
     * listener who left the reader had no compact bar to come back through, no chapter list,
     * no speed and no sleep timer — and iOS, where read-aloud has always been a second
     * source inside the one `PlayerCentre`, had all four.
     *
     * **[PlaybackCentre.attach] rather than [PlaybackCentre.start], and the caller starts
     * first.** The voice owns its own beginning: it asks for audio focus, binds a speech
     * engine and walks to the first sentence, and only then is there a session to draw.
     * Started from here instead, the centre would publish an idle source and let it go in
     * the same breath — [PlaybackCentre.publish] drops a source whose session is not active,
     * which is exactly what an unstarted voice looks like.
     *
     * **[memory] is dropped, not kept.** See [rememberForResumption]: a voice has no file
     * for media3 to put back, so a record of one would be a resumption that plays silence.
     */
    fun startVoice(source: PlayerSource) {
        memory = null
        current = null
        voice = source
        centre.attach(source)
    }

    /**
     * Ends a voice session this centre is still holding.
     *
     * What the voice's own teardown calls, so the compact bar and the player go with the
     * voice rather than outliving it. A session the voice has already lost — displaced by an
     * audiobook, which stops the voice on its way in — is left alone: [voice] is null by
     * then, and stopping here would stop the book that replaced it.
     */
    fun stopVoice(source: PlayerSource) {
        if (voice !== source) return
        stop()
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
        // through its fade. Through the source rather than through the controller this host
        // holds: the fade belongs to whatever is making the sound, and a controller reaches
        // only the decoder. A voice has no gain and fades by not fading — see
        // [PlayerSource.setVolume].
        centre.setVolume(1f)
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
                centre.setVolume(next.gain)
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
        // Only where a seek lands somewhere a listener can be put back. A voice is not
        // scrubbable — it has no clock to rewind thirty seconds of — and seeking it would
        // begin the chapter again rather than resume it a little earlier. iOS's
        // `sleepTimerElapsed` guards the same call with the same question.
        if (playing?.isScrubbable == true) rewound?.let(centre::seek)
        // `audio-playback` asks the audio to fade rather than be cut. A voice has no fade to
        // give, so it finishes the sentence it is saying instead, which is the same promise
        // kept the only way a sentence can keep it.
        if (playing?.isPlaying == true) centre.stopAtSentenceEnd()
        centre.setVolume(1f)
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

    /**
     * Moves to the start of a part, whichever way this publication's parts are laid out.
     *
     * Through the centre, so the source that holds the session answers it. It used to go
     * straight to [current], which is a narrated book or nothing — so choosing a chapter
     * while the voice was speaking moved nothing and still wrote a position.
     */
    fun seekToPart(index: Int) = centre.seekToPart(index)

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
