package app.storyarc.feature.epubreader

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
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
    val context: Context,
    publication: Publication,
    /** Reports the sentence the engine has started saying. */
    private val onSentence: suspend (Sentence) -> Unit,
) {

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
    val session: StateFlow<PlaybackSession> = _session.asStateFlow()

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
     * Starts speaking from where the reader is.
     *
     * The reader's own locator, not the top of the resource: a reader who presses play in
     * the middle of a chapter means "from here", and starting at the chapter's first
     * paragraph would make them listen back to what they have already read.
     */
    fun start(from: Locator?) {
        if (!sentences.isSpeakable) return
        if (audio?.requestAudioFocus(focusRequest) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            return
        }
        sentences.restart(from)
        _session.value = _session.value.started()
        withEngine { speakNext(forward = true) }
    }

    /** Pause and play, from the reader's own control or from the lock screen's. */
    fun toggle() {
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
    fun skip(forward: Boolean) {
        if (!_session.value.isActive) return
        _session.value = _session.value.started()
        speakNext(forward = forward)
    }

    /** Stops: the listener closed it, or the book ran out of words. */
    fun stop() = finish(_session.value.stopped())

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
    fun release() {
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
        override fun onStart(utteranceId: String?) = Unit

        override fun onDone(utteranceId: String?) {
            // The engine finished a sentence of its own accord. A sentence it was told to
            // stop reports `onStop`, not this, so a pause never runs on into the next one.
            scope.launch { if (_session.value.isPlaying) speakNext(forward = true) }
        }

        override fun onStop(utteranceId: String?, interrupted: Boolean) = Unit

        // Abstract on the base class, deprecated on the base class. It has to be
        // overridden and it is never the one called on any version this app supports.
        @Suppress("OVERRIDE_DEPRECATION")
        override fun onError(utteranceId: String?) = Unit

        override fun onError(utteranceId: String?, errorCode: Int) {
            // One sentence the engine could not say is not a reason to end the book: the
            // usual cause is a language it has no voice for, in a single quoted line.
            scope.launch { if (_session.value.isPlaying) speakNext(forward = true) }
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
        engine.speak(
            sentence.text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            sentence.locator.href.toString(),
        )
        scope.launch { onSentence(sentence) }
    }

    private companion object {
        val SPEECH_ATTRIBUTES: AudioAttributes =
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
    }
}
