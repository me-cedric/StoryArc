package app.storyarc.feature.epubreader

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.content.ContextCompat
import app.storyarc.core.playback.InterruptionOutcome
import app.storyarc.core.playback.PlaybackSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication

/**
 * The book, read out loud.
 *
 * `ebook-reader`: speech "begins at the current position, the spoken sentence is
 * highlighted, and the page follows", it keeps going when the app is backgrounded, and the
 * session "SHALL outlive the screen it was started from".
 *
 * Three parts, and only one of them is a decision this project makes. [SpokenSentences]
 * answers what to say and where it is in the book. The platform's `TextToSpeech` says it.
 * What a pause *means* — and therefore whether a finished phone call starts the book again
 * — is [PlaybackSession], which is asserted without a speaker on both platforms.
 *
 * The engine is the device's own, so a reader hears the voice they installed and the
 * languages they downloaded, and nothing about the book leaves the device to be spoken.
 *
 * **This is the engine and the cursor, and nothing above them.** Who holds it, what the
 * notification says, and where the reached position is written are [ReadAloudHost]'s, which
 * is what lets the whole of it outlive an activity: this owns a scope of its own rather
 * than borrowing a screen's, and its session flow is the only thing it tells anybody.
 *
 * iOS's `ReadAloudCentre` holds Readium's `PublicationSpeechSynthesizer` in the same place
 * for the same reason — see ADR-0017 for why the two engines are not the same shape.
 */
internal class ReadAloudController(
    /** The application context: this outlives every activity, and so must its context. */
    override val context: Context,
    publication: Publication,
    /** Reports the sentence the engine has started saying. */
    private val onSentence: suspend (Sentence) -> Unit,
) : SpokenVoice {

    /**
     * The scope the walk runs in.
     *
     * Its own, not an activity's `lifecycleScope`. That borrowed scope was the Android half
     * of the defect this change fixes: finishing the reader cancelled the walk, so a
     * listener who closed the book heard the current sentence out and then silence.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val sentences = SpokenSentences(publication)

    private val _session = MutableStateFlow(PlaybackSession())
    override val session: StateFlow<PlaybackSession> = _session.asStateFlow()

    private val audio = context.getSystemService(AudioManager::class.java)

    /**
     * The engine, built on the first press rather than when the book opens.
     *
     * Constructing a `TextToSpeech` binds to another process and can take a second on a
     * cold device. A reader who never presses play should not pay for that, and the
     * control's presence is [SpokenSentences]'s answer rather than the engine's.
     */
    private var engine: TextToSpeech? = null

    /** What the engine is saying, so the page can be moved to it once it starts. */
    private var current: Sentence? = null

    /** Utterance errors since the last sentence the engine finished. Reset in `onDone`. */
    private var consecutiveErrors = 0

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            // Something else wants the speaker for a moment: a navigation direction, a
            // notification with a sound, an incoming call being announced.
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK,
            -> pauseFor(interrupted = true)
            // It gave the speaker back, or took it for good. Which of those means what is
            // the session's decision, not this listener's — see
            // [PlaybackSession.endingInterruption].
            AudioManager.AUDIOFOCUS_GAIN -> endInterruption(mayResume = true)
            AudioManager.AUDIOFOCUS_LOSS -> endInterruption(mayResume = false)
        }
    }

    private val focusRequest =
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(SPEECH_ATTRIBUTES)
            .setOnAudioFocusChangeListener(focusListener)
            .setWillPauseWhenDucked(true)
            .build()

    /**
     * Headphones, or a wired adapter, come out.
     *
     * A speech source over the shared player would get this from media3's own
     * `setHandleAudioBecomingNoisy` for free; until it does, nothing else on this path hears
     * it at all. Paused as a listener pause — the ordinary button's own outcome — so
     * reconnecting the same or a different output never starts the voice again on its own.
     */
    private val becomingNoisy = NoisyAudioPause(onNoisy = { pauseFor(interrupted = false) })

    /**
     * Starts speaking from where the reader is.
     *
     * The reader's own locator, not the top of the resource: a reader who presses play in
     * the middle of a chapter means "from here", and starting at the chapter's first
     * paragraph would make them listen back to what they have already read.
     */
    override fun start(from: Locator?) {
        // Not re-checked here: `EpubReaderActivity` only offers this control once
        // `SpokenSentences.isSpeakable` has already walked the publication and found a
        // word, so a `start()` with nothing to say would mean that gate was bypassed.
        if (audio?.requestAudioFocus(focusRequest) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            return
        }
        becomingNoisy.register(context)
        stoppingAtSentenceEnd = false
        sentences.restart(from)
        _session.value = _session.value.started()
        withEngine { speakNext(forward = true) }
    }

    /** Pause and play, from the reader's own control or from the lock screen's. */
    override fun toggle() {
        stoppingAtSentenceEnd = false
        if (_session.value.isPlaying) {
            pauseFor(interrupted = false)
        } else {
            val next = _session.value.resumed()
            if (next == _session.value) return
            _session.value = next
            resume()
        }
    }

    /**
     * The next sentence, and the one before.
     *
     * `ebook-reader` names "sentence skip" for the lock screen, and the reader looking at
     * the page gets the same two. Skipping while paused starts speaking again, which is
     * what the gesture means: nobody skips a sentence to keep hearing silence.
     */
    override fun skip(forward: Boolean) {
        if (!_session.value.isActive) return
        stoppingAtSentenceEnd = false
        _session.value = _session.value.started()
        speakNext(forward = forward)
    }

    /**
     * How fast the voice speaks.
     *
     * `TextToSpeech.setSpeechRate` takes the same multiplier the player states, so there is
     * no mapping to get wrong. It applies to the **next** utterance rather than to the one
     * being said: the engine has already queued the current sentence, and a rate changed
     * part way through it is a sentence that changes pace mid-word. A listener who moves
     * the slider hears the new pace at the next sentence, which for spoken word is about a
     * second away.
     */
    override fun setSpeed(rate: Double) {
        speechRate = rate.toFloat()
        engine?.setSpeechRate(speechRate)
    }

    /**
     * The rate the engine is asked for, kept because the engine is built on the first press.
     *
     * A listener who chose a speed for the last book, or moved the slider before the engine
     * had bound, would otherwise be given the device's default — the setting would appear to
     * take and nothing would change pace.
     */
    private var speechRate = 1f

    /**
     * Moves the walk to a chapter the listener chose from the player's list.
     *
     * Speaking again afterwards, because choosing a chapter is choosing to hear it — the
     * same reading a skip takes. A chapter the publication does not hold leaves the voice
     * where it was rather than sending it back to the first page.
     */
    override fun jumpTo(resourceIndex: Int) {
        if (!_session.value.isActive) return
        stoppingAtSentenceEnd = false
        walking?.cancel()
        walking = scope.launch {
            val moved = withContext(Dispatchers.IO) { sentences.restartAtResource(resourceIndex) }
            if (!moved) return@launch
            _session.value = _session.value.started()
            speakNext(forward = true)
        }
    }

    /**
     * Goes quiet once the sentence being said has finished.
     *
     * The sleep timer's ending. `audio-playback` asks for a fade rather than a cut, and a
     * voice has no gain to fade — so the sentence is allowed to finish and the next is not
     * begun. [progress]'s `onDone` is where that is decided, because it is the one report
     * that means the engine reached the end of an utterance of its own accord.
     *
     * Nothing is stopped here. A stop would be the cut this exists to avoid.
     */
    override fun stopAtSentenceEnd() {
        if (!_session.value.isPlaying) return
        stoppingAtSentenceEnd = true
    }

    /**
     * Set by [stopAtSentenceEnd], and spent by the next sentence that finishes.
     *
     * Cleared by everything that means the listener wants to go on — a play, a skip, a
     * chapter chosen — so a sleep timer the listener cancelled by pressing play does not
     * silence the book one sentence later. iOS's `SpokenSource` holds the same flag.
     */
    private var stoppingAtSentenceEnd = false

    /** Stops: the listener closed it, or the book ran out of words. */
    override fun stop() = finish(_session.value.stopped())

    /**
     * Stops because the audio was taken and not given back.
     *
     * Named apart from [stop] because the cause is the difference worth reading at the call
     * site, not the state that follows — both leave a silent, controlless session, and
     * `ebook-reader` asks for both by name.
     */
    private fun lostAudio() = finish(_session.value.lostAudio())

    private fun finish(next: PlaybackSession) {
        walking?.cancel()
        current = null
        engine?.stop()
        audio?.abandonAudioFocusRequest(focusRequest)
        becomingNoisy.unregister(context)
        // Last, because it is what [ReadAloudHost] is watching: everything this session
        // holds is already given up by the time the host hears that it ended.
        _session.value = next
    }

    /**
     * Gives up the engine and the scope.
     *
     * Called by [ReadAloudHost] when the session has ended, never by a screen. An activity
     * calling this is what used to make closing the book the same act as stopping the voice.
     */
    override fun release() {
        stop()
        engine?.shutdown()
        engine = null
        scope.cancel()
    }

    /**
     * Says the sentence that was interrupted again, from its beginning.
     *
     * `TextToSpeech` has no notion of resuming part-way through an utterance, so the
     * alternative would be skipping the rest of the sentence — and half a sentence lost is
     * worse than one sentence heard twice.
     */
    private fun resume() {
        current?.let { withEngine { speak(it) } } ?: withEngine { speakNext(forward = true) }
    }

    private fun pauseFor(interrupted: Boolean) {
        val next =
            if (interrupted) _session.value.interrupted() else _session.value.pausedByListener()
        if (next == _session.value) return
        engine?.stop()
        _session.value = next
    }

    /**
     * What the end of an interruption does.
     *
     * The three answers are the session's, not this class's. Before there were three, focus
     * taken for good was answered here with a plain stop and iOS answered it with nothing
     * at all — the case `ebook-reader` names as "audio taken for good stops the session
     * rather than leaving it paused for ever".
     */
    private fun endInterruption(mayResume: Boolean) {
        when (_session.value.endingInterruption(mayResume)) {
            InterruptionOutcome.NOTHING -> Unit
            InterruptionOutcome.RESUME -> {
                _session.value = _session.value.resumed()
                resume()
            }
            InterruptionOutcome.LOST -> lostAudio()
        }
    }

    /**
     * Runs [body] once the engine is up.
     *
     * `TextToSpeech` reports readiness through a callback rather than a constructor, so
     * the first press has to wait for it and every press after it must not.
     */
    private fun withEngine(body: () -> Unit) {
        engine?.let { body(); return }
        engine = TextToSpeech(context) { status ->
            val ready = engine
            if (status == TextToSpeech.SUCCESS && ready != null) {
                ready.setOnUtteranceProgressListener(progress)
                // Before the first word, so a speed chosen while the engine was still
                // binding is the speed the first sentence is said at.
                ready.setSpeechRate(speechRate)
                body()
            } else {
                // No engine on this device, or none that would start. Nothing is said and
                // the session goes back to idle, so the reader gets their play control back
                // rather than a transport that does nothing.
                stop()
            }
        }
    }

    private val progress = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {
            // The engine is actually saying it now, so this is when the reached position is
            // recorded and the highlight moves -- not when the sentence was only queued. A
            // session that errors on every utterance before this point never advances past
            // the sentence it last started, instead of racing to the end of the book.
            scope.launch {
                val sentence = current?.takeIf { it.locator.href.toString() == utteranceId }
                    ?: return@launch
                onSentence(sentence)
            }
        }

        override fun onDone(utteranceId: String?) {
            // The engine finished a sentence of its own accord. A sentence it was told to
            // stop reports `onStop`, not this, so a pause never runs on into the next one.
            // Only a finished sentence ends a run of errors: an engine can start an
            // utterance and then fail it, and that start is not a sentence said.
            scope.launch {
                consecutiveErrors = 0
                if (!_session.value.isPlaying) return@launch
                // The sleep timer asked for the sentence to finish, and it has. A listener
                // pause rather than a stop, so the book is where they left it and play
                // starts it again — `audio-playback` asks the position to be recorded and
                // the session to stay, not to end.
                if (stoppingAtSentenceEnd) {
                    stoppingAtSentenceEnd = false
                    pauseFor(interrupted = false)
                    return@launch
                }
                speakNext(forward = true)
            }
        }

        override fun onStop(utteranceId: String?, interrupted: Boolean) = Unit

        // Abstract on the base class, deprecated on the base class. It has to be
        // overridden and it is never the one called on any version this app supports.
        @Suppress("OVERRIDE_DEPRECATION")
        override fun onError(utteranceId: String?) = Unit

        override fun onError(utteranceId: String?, errorCode: Int) {
            scope.launch {
                if (!_session.value.isPlaying) return@launch
                consecutiveErrors += 1
                // One sentence the engine could not say is not by itself a reason to end the
                // book -- the usual cause is a language it has no voice for, in a single
                // quoted line. An engine-level code, or enough of those in a row, means the
                // walk cannot continue: see [shouldEndAfterSpeechError].
                if (shouldEndAfterSpeechError(errorCode, consecutiveErrors)) {
                    stop()
                } else {
                    speakNext(forward = true)
                }
            }
        }
    }

    /**
     * The walk in progress.
     *
     * Cancelled before another starts. [SpokenSentences] holds a cursor and reads from disk
     * off the main thread, so two skips in quick succession would otherwise be two
     * coroutines moving the same cursor past each other -- and the sentence that arrived
     * second would not be the one the reader asked for.
     */
    private var walking: Job? = null

    private fun speakNext(forward: Boolean) {
        walking?.cancel()
        walking = scope.launch {
            val sentence = withContext(Dispatchers.IO) {
                if (forward) sentences.next() else sentences.previous()
            }
            if (sentence == null) {
                // The end of the publication, or its beginning. Everything the reader's own
                // stop does happens here too, or the lock screen keeps offering to play a
                // book that has run out of words.
                if (forward) stop()
                return@launch
            }
            speak(sentence)
        }
    }

    private fun speak(sentence: Sentence) {
        current = sentence
        val engine = engine ?: return
        sentence.language?.let { engine.language = it }
        val queued = engine.speak(
            sentence.text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            sentence.locator.href.toString(),
        )
        // A refused call gets neither `onStart` nor `onError`: nothing else will ever end
        // this session, so it has to happen here, with the last *started* sentence's
        // position already the one on record.
        if (queued != TextToSpeech.SUCCESS) stop()
    }

    private companion object {
        val SPEECH_ATTRIBUTES: AudioAttributes =
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
    }
}

/**
 * Whether one more utterance error is the end of the read-aloud session.
 *
 * Pure, so the engine/utterance split and the consecutive count are a plain JVM test rather
 * than code only a real `TextToSpeech` service can exercise. [ReadAloudController] is the one
 * caller and holds the count; this only answers what it means.
 *
 * An engine-level code ends the session at once, because the cause is the synthesis service
 * and not one sentence. Any other code ends it after [MAX_CONSECUTIVE_SPEECH_ERRORS] in a row.
 * One such error is usually a quoted line in a language that has no voice on the device. That
 * is not a reason to stop. A run of them is a book the engine cannot say, and walking every
 * sentence to the end of the book in silence is worse than stopping.
 */
internal fun shouldEndAfterSpeechError(errorCode: Int, consecutiveErrors: Int): Boolean =
    isEngineLevelSpeechError(errorCode) || consecutiveErrors >= MAX_CONSECUTIVE_SPEECH_ERRORS

/**
 * An error naming the synthesis service or its output, rather than one sentence.
 *
 * `ERROR_NOT_INSTALLED_YET` is not in this list. It names one voice whose data is still
 * downloading, which is the "one quoted line" case above, so the consecutive count decides.
 */
internal fun isEngineLevelSpeechError(errorCode: Int): Boolean = when (errorCode) {
    TextToSpeech.ERROR_SERVICE,
    TextToSpeech.ERROR_OUTPUT,
    TextToSpeech.ERROR_NETWORK,
    TextToSpeech.ERROR_NETWORK_TIMEOUT,
    -> true
    else -> false
}

/** A small number: enough to tell "one sentence" from "every sentence", and no more. */
internal const val MAX_CONSECUTIVE_SPEECH_ERRORS = 3

/**
 * Calls [onNoisy] while registered, for `ACTION_AUDIO_BECOMING_NOISY`.
 *
 * Its own type, beside [ReadAloudController] rather than inside it, so the registration and
 * the broadcast are a Robolectric test against a plain [Context] — nothing here needs the
 * `TextToSpeech` or the Readium `Publication` the rest of the controller does.
 */
internal class NoisyAudioPause(private val onNoisy: () -> Unit) : BroadcastReceiver() {

    private var registered = false

    override fun onReceive(context: Context, intent: Intent) = onNoisy()

    /** While the voice speaks, never before and never twice. */
    fun register(context: Context) {
        if (registered) return
        ContextCompat.registerReceiver(
            context,
            this,
            IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        registered = true
    }

    fun unregister(context: Context) {
        if (!registered) return
        context.unregisterReceiver(this)
        registered = false
    }
}
