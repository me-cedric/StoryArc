package app.storyarc.feature.epubreader

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
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
 * platform's media controls carry the title and offer play, pause and sentence skip.
 *
 * Three parts, and only one of them is a decision this project makes. [SpokenSentences]
 * answers what to say and where it is in the book. The platform's `TextToSpeech` says it.
 * What a pause *means* — and therefore whether a finished phone call starts the book again
 * — is [ReadAloudSession], which is asserted without a speaker on both platforms.
 *
 * The engine is the device's own, so a reader hears the voice they installed and the
 * languages they downloaded, and nothing about the book leaves the device to be spoken.
 *
 * iOS's `EpubReadAloud` does the same job against Readium's `PublicationSpeechSynthesizer`,
 * which is the iOS-only half of the same toolkit — see ADR-0017 for why the two halves are
 * not the same shape.
 */
internal class ReadAloudController(
    private val context: Context,
    private val scope: CoroutineScope,
    publication: Publication,
    /** Draws the sentence and brings the page to it. */
    private val onSentence: suspend (Sentence) -> Unit,
    /** Withdraws the highlight when the voice stops. */
    private val onSilence: suspend () -> Unit,
) {

    private val sentences = SpokenSentences(publication)

    /** Whether the control belongs on screen at all. */
    val isSpeakable: Boolean get() = sentences.isSpeakable

    private val _session = MutableStateFlow(ReadAloudSession())
    val session: StateFlow<ReadAloudSession> = _session.asStateFlow()

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
            // It gave the speaker back. Whether that resumes anything is the session's
            // decision, not this listener's.
            AudioManager.AUDIOFOCUS_GAIN -> {
                val next = _session.value.interruptionEnded(mayResume = true)
                if (next != _session.value) {
                    _session.value = next
                    resume()
                }
                announce()
            }
            // Taken for good — another app started playing and kept the focus.
            AudioManager.AUDIOFOCUS_LOSS -> stop()
        }
    }

    private val focusRequest =
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(SPEECH_ATTRIBUTES)
            .setOnAudioFocusChangeListener(focusListener)
            .setWillPauseWhenDucked(true)
            .build()

    /** What the lock screen says, refreshed whenever the chapter or the state changes. */
    var label: SpokenLabel = SpokenLabel("", null)
        set(value) {
            field = value
            if (_session.value.isActive) announce()
        }

    /**
     * Starts speaking from where the reader is.
     *
     * The reader's own locator, not the top of the resource: a reader who presses play in
     * the middle of a chapter means "from here", and starting at the chapter's first
     * paragraph would make them listen back to what they have already read.
     */
    fun start(from: Locator?) {
        if (!isSpeakable) return
        if (audio?.requestAudioFocus(focusRequest) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            return
        }
        sentences.restart(from)
        _session.value = _session.value.started()
        announce()
        withEngine { speakNext(forward = true) }
    }

    /** Pause and play, from the reader's own control or from the lock screen's. */
    fun toggle() {
        if (_session.value.isSpeaking) {
            pauseFor(interrupted = false)
        } else {
            val next = _session.value.resumed()
            if (next == _session.value) return
            _session.value = next
            resume()
            announce()
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
        announce()
    }

    /** Stops, clears the highlight, and hands the lock screen back. */
    fun stop() {
        val wasActive = _session.value.isActive
        walking?.cancel()
        _session.value = _session.value.stopped()
        current = null
        engine?.stop()
        audio?.abandonAudioFocusRequest(focusRequest)
        ReadAloudService.dismiss(context)
        if (wasActive) scope.launch { onSilence() }
    }

    /** Called when the screen goes away: nothing outlives the book it is reading. */
    fun release() {
        stop()
        engine?.shutdown()
        engine = null
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
            if (interrupted) _session.value.interrupted() else _session.value.pausedByReader()
        if (next == _session.value) return
        _session.value = next
        engine?.stop()
        announce()
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
            scope.launch { if (_session.value.isSpeaking) speakNext(forward = true) }
        }

        override fun onStop(utteranceId: String?, interrupted: Boolean) = Unit

        // Abstract on the base class, deprecated on the base class. It has to be
        // overridden and it is never the one called on any version this app supports.
        @Suppress("OVERRIDE_DEPRECATION")
        override fun onError(utteranceId: String?) = Unit

        override fun onError(utteranceId: String?, errorCode: Int) {
            // One sentence the engine could not say is not a reason to end the book: the
            // usual cause is a language it has no voice for, in a single quoted line.
            scope.launch { if (_session.value.isSpeaking) speakNext(forward = true) }
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
        // Deliberately no announcement here. The transport shows a state, and saying a
        // sentence does not change one — refreshing the notification every few seconds
        // would be a service start per sentence for a picture that did not move.
        scope.launch { onSentence(sentence) }
    }

    /**
     * Puts the book on the lock screen, or takes it off.
     *
     * A foreground service, because that is the only thing on Android that keeps a process
     * speaking once its screen is gone — and because a media-playback service is what puts
     * the transport where a reader reaches for it.
     */
    private fun announce() {
        if (_session.value.isActive) {
            ReadAloudService.show(context, label, _session.value.isSpeaking)
        } else {
            ReadAloudService.dismiss(context)
        }
    }

    private companion object {
        val SPEECH_ATTRIBUTES: AudioAttributes =
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
    }
}
