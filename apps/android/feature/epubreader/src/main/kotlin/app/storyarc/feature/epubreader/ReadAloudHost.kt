package app.storyarc.feature.epubreader

import android.content.Context
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.TotalProgression
import app.storyarc.core.persistence.ProgressStore
import app.storyarc.core.playback.PlaybackSession
import java.lang.ref.WeakReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

/**
 * The screen drawing the sentence being spoken, while one is on screen.
 *
 * Everything on this interface needs a navigator, which is exactly why none of it belongs
 * to the session: a listener who closes the book still hears the voice, and there is simply
 * nothing to draw until they open it again.
 */
internal interface SpokenSentenceFollower {
    /** Draws the sentence and brings the page to it. */
    suspend fun drawSpokenSentence(sentence: Sentence)

    /** Takes the spoken highlight off the page when the voice stops. */
    suspend fun withdrawSpokenHighlight()
}

/**
 * The voice, which outlives the screen that started it.
 *
 * `ebook-reader`: "the session SHALL outlive the screen it was started from", and closing
 * the publication returns the listener to what they were doing "rather than being kept in
 * the book". Android was most of the way there already — the voice has always run in a
 * `mediaPlayback` foreground service, so it survives the app being backgrounded — but the
 * [ReadAloudController] that drives it belonged to `EpubReaderActivity`, and `onDestroy`
 * released it. Finishing the reader while the app stayed in the foreground stopped the
 * voice, which is a different case from backgrounding and the one nothing answered.
 *
 * **Where this lives, and why here.** An `object`, because a process-wide singleton is the
 * only lifetime longer than every activity, and because `ebook-reader` allows exactly one
 * session: "two books cannot be read aloud at once". It lives in this module rather than a
 * new one because it holds a Readium `Publication`, and ADR-0005 keeps Readium behind this
 * module — a feature module may not depend on another, and the app module already depends
 * on this one to open the reader.
 *
 * **What it owns and what it does not.** It owns the controller, the book being spoken,
 * where the position is written, and the notification the service posts. It does not own
 * the highlight or the page: those need a navigator, so an activity that happens to be on
 * screen registers as a [SpokenSentenceFollower] and is let go without a word when it goes.
 *
 * iOS's `ReadAloudCentre` is the same object with the same three jobs.
 */
internal object ReadAloudHost {

    /**
     * The scope the session's own work runs in.
     *
     * Not an activity's `lifecycleScope`, which is the whole ownership change: work
     * scheduled on a dying activity's scope is cancelled with it, and the voice is not.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val _session = MutableStateFlow(PlaybackSession())

    /** Whether the voice is running, and what silenced it if it is not. */
    val session: StateFlow<PlaybackSession> = _session.asStateFlow()

    private val _book = MutableStateFlow<SpokenBook?>(null)

    /**
     * The book being spoken, or null when nothing is.
     *
     * What the notification says, and where its way back goes. Null is also the answer to
     * "is there a transport at all".
     */
    val book: StateFlow<SpokenBook?> = _book.asStateFlow()

    private var controller: ReadAloudController? = null
    private var position: SpokenPosition? = null
    private var watching: Job? = null

    /**
     * The screen drawing the sentence, while one is on screen.
     *
     * Weak, and that is the whole of the ownership change: the session refers to the
     * screen, never the other way round, so an activity going away cannot take the voice
     * with it.
     */
    private var follower: WeakReference<SpokenSentenceFollower>? = null

    /** The sentence being spoken, kept so a reader that opens the book can draw it. */
    private var spoken: Sentence? = null

    // MARK: starting, and changing hands

    /**
     * Takes a session over from the reader that started it.
     *
     * Everything the session needs afterwards is passed in here, because after this call
     * the activity is free to be destroyed: the publication to walk, where to write the
     * position, and what to say about the book. The follower is the one thing allowed to go.
     */
    fun begin(
        context: Context,
        book: SpokenBook,
        publication: Publication,
        position: SpokenPosition,
        from: Locator?,
        drawnBy: SpokenSentenceFollower,
    ) {
        end()
        val voice = ReadAloudController(
            context = context.applicationContext,
            publication = publication,
            onSentence = ::sentenceSpoken,
        )
        controller = voice
        this.position = position
        this.follower = WeakReference(drawnBy)
        _book.value = book
        // What the notification's and the lock screen's buttons reach. One session at a
        // time, so one set of commands at a time, and [finish] takes them back down.
        ReadAloudService.commands = object : ReadAloudCommands {
            override fun toggle() = this@ReadAloudHost.toggle()
            override fun skip(forward: Boolean) = this@ReadAloudHost.skip(forward)
            override fun stop() = end()
        }
        watching = scope.launch {
            voice.session.collect { next ->
                // A session that has already been finished has nothing left to say. Without
                // this an ending emission could arrive after the next session had started —
                // a `StateFlow` collector resumes on its dispatcher rather than inside the
                // write — and tear down the book that had just replaced it.
                if (controller !== voice) return@collect
                _session.value = next
                if (next.isActive) announce() else finish(voice)
            }
        }
        voice.start(from)
    }

    /** A reader has opened the book being spoken, and will draw its sentence. */
    fun adopt(drawnBy: SpokenSentenceFollower) {
        if (controller == null) return
        follower = WeakReference(drawnBy)
    }

    /**
     * The screen drawing the sentence has gone.
     *
     * The session is not touched. That is the change: `onDestroy` used to release the
     * controller, and now it only says that nobody is drawing. The highlight goes with the
     * navigator that held it, and comes back when a reader adopts the session again.
     */
    fun release(drawnBy: SpokenSentenceFollower) {
        if (follower?.get() !== drawnBy) return
        follower = null
    }

    /**
     * Draws the sentence again for a reader that has just adopted the session.
     *
     * `ebook-reader`: "reopening the publication resumes at the sentence being spoken,
     * without the voice stopping or repeating".
     */
    suspend fun redrawSpokenSentence() {
        val sentence = spoken ?: return
        follower?.get()?.drawSpokenSentence(sentence)
    }

    // MARK: the transport

    /** Pause and play, from wherever the listener reached for it. */
    fun toggle() {
        controller?.toggle()
    }

    /** The next sentence, and the one before. */
    fun skip(forward: Boolean) {
        controller?.skip(forward)
    }

    /** Ends the session: the listener closed it, or the book ran out of words. */
    fun end() {
        val ending = controller ?: return
        ending.stop()
        // Torn down here rather than left to the flow, because the caller may be about to
        // start the next session and the teardown has to have happened by then.
        finish(ending)
    }

    /**
     * The one way a session stops.
     *
     * Reached whoever ended it — the listener's stop, the end of the publication, or the
     * audio being taken for good all arrive here as the same idle session. The position is
     * not written here because it has already been written: see [sentenceSpoken].
     */
    private fun finish(ending: ReadAloudController) {
        if (controller !== ending) return
        controller = null
        position = null
        spoken = null
        val drawing = follower?.get()
        follower = null
        watching?.cancel()
        watching = null
        ending.release()
        ReadAloudService.commands = null
        ReadAloudService.dismiss(ending.context)
        _book.value = null
        _session.value = PlaybackSession()
        scope.launch { drawing?.withdrawSpokenHighlight() }
    }

    // MARK: what the voice is on

    private suspend fun sentenceSpoken(sentence: Sentence) {
        spoken = sentence
        val was = _book.value
        _book.value = was?.copy(chapter = sentence.locator.title ?: was.chapter)
        // Only when the line actually changed. The transport shows a state, and saying a
        // sentence does not change one — refreshing the notification every few seconds
        // would be a service start per sentence for a picture that did not move.
        if (was?.label != _book.value?.label) announce()
        recordReached(sentence)
        follower?.get()?.drawSpokenSentence(sentence)
    }

    /**
     * Writes down where the voice got to.
     *
     * On every sentence, not only when the session ends. A process the system reclaims gets
     * no ending at all, and the only position that survives one is a position already
     * written. While a reader is on screen its navigator writes at this same rate, because
     * the page follows the voice; this is that rate carrying on after the screen has gone.
     */
    private fun recordReached(sentence: Sentence) {
        val writer = position ?: return
        val reached = writer.reached(sentence.locator)
        if (!reached.isRecordable) return
        scope.launch { writer.record(reached) }
    }

    /**
     * Puts the book on the lock screen and in the shade, or takes it off.
     *
     * A foreground service, because that is the only thing on Android that keeps a process
     * speaking once its screen is gone — and because a media-playback service is what puts
     * the transport where a listener reaches for it. iOS reaches the same two places
     * through `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` instead.
     */
    private fun announce() {
        val voice = controller ?: return
        val book = _book.value ?: return
        ReadAloudService.show(voice.context, book, _session.value.isPlaying)
    }
}

/**
 * Where a session's position goes, with no screen involved.
 *
 * Everything the writer needs is copied out of the reader when the session begins, so the
 * write does not depend on an activity, a navigator or a view model that may be long gone
 * by the time the voice reaches the sentence being recorded.
 *
 * iOS pins the same type in `ReadAloudCentre.swift`.
 */
internal data class SpokenPosition(
    val identity: PublicationIdentity,
    /** The reading order's hrefs, which is what turns a locator into a percentage. */
    val readingOrder: List<String>,
    val store: ProgressStore?,
) {

    /** Turns Readium's locator into the position `reading-progress` records. */
    fun reached(locator: Locator): ReachedPosition = ReachedPosition(
        locator = locator.toJSON().toString(),
        // The rule lives in `:core:model` so both platforms answer it the same way, and
        // because it is subtler than it looks: in scroll mode Readium reports `0.0` rather
        // than nothing.
        progression = TotalProgression.resolve(
            reported = locator.locations.totalProgression,
            within = locator.locations.progression ?: 0.0,
            resourceIndex = TotalProgression.indexOf(locator.href.toString(), readingOrder),
            resourceCount = readingOrder.size,
        ),
    )

    suspend fun record(reached: ReachedPosition) {
        store?.save(reached.record(identity, System.currentTimeMillis()))
    }
}
