package app.storyarc.core.playback

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The one authority on what is speaking, whichever engine is behind it.
 *
 * `audio-playback`: "the first stops and its position is recorded before the second begins,
 * because two books speaking at once is never what was meant". [SessionHandover] has always
 * said what opening a publication *means*; this is who is allowed to answer it.
 *
 * **What was wrong before this existed.** The question was asked of one engine at a time.
 * `EpubReaderActivity` asked `SessionHandover.opening(bookId, ReadAloudHost.book.value?.id)`,
 * which sees only the voice, and `PlaybackHost.start` displaced only whatever `PlaybackCentre`
 * held, which is only ever a narrated file. So a narrated audiobook and a spoken EPUB could
 * speak at the same time — the one thing the requirement above forbids by name.
 *
 * **Why this is a separate object on Android and is not one on iOS.** There, read-aloud is
 * already a second `PlaybackSource` inside the single `PlayerCentre`, so the centre *is* the
 * authority and `handover(opening:)` is a method on it. Here the two engines are still two:
 * `PlaybackHost` drives audio through a media3 `MediaController` bound to a
 * `MediaLibraryService`, and `ReadAloudHost` drives Readium's speech through a
 * `mediaPlayback` service of its own — two services, two notifications, and collapsing them
 * is task 6.1 rather than this defect. Nor could the centre hold both: `:feature:epubreader`
 * depends on `:core:playback` and never the reverse, so the thing that owns the voice cannot
 * be the thing that arbitrates. What is mirrored is the guarantee, which is ADR-0001's whole
 * point: the rule is shared, the idiom is each platform's.
 *
 * **It also holds the word a displacement owes.** `ebook-reader` asks that a listener whose
 * voice was stopped by opening another publication be told once, and the only object that
 * knows a displacement happened — as opposed to a stop, a book running out, or audio taken —
 * is this one. iOS holds the same notice on `PlayerCentre`, because there the centre is the
 * arbiter. [voiceStopped] outlives every screen, which is what lets the screen that caused the
 * displacement show it and a later screen find nothing.
 *
 * **A class with a shared instance, exactly as `PlaybackCentre` is a class behind
 * `PlaybackHost`** — the rules below are asserted without a process, and `SpokenAudioTest`
 * makes its own.
 *
 * Main thread only, like everything else in this module: media3 requires it, and both
 * speakers already run on `Dispatchers.Main.immediate`.
 */
class SpokenAudio {

    /**
     * Which kind of speaker something is.
     *
     * The one fact about a speaker's identity this authority is allowed to know, and it is
     * known for one reason: [VoiceStoppedNotice]'s second rule says only a *voice* owes a word.
     * iOS asks the same question of the publication's format — a fact about the file — because
     * its one centre holds a `SpokenBook`; here each host knows what engine it is, and says so.
     */
    enum class Kind {
        /** A synthesised voice reading a publication's text. Displacing one owes a word. */
        VOICE,

        /** A narrated file. Displacing one owes nothing. */
        NARRATOR,
    }

    /**
     * What a speaker is speaking: the id [SessionHandover.opening] compares, and the title a
     * displacement notice names. Two facts about the same session, so one value.
     */
    data class Spoken(val id: String, val title: String)

    /**
     * Something that can make a publication speak, as this authority sees it.
     *
     * Deliberately three members, and narrow for the reason it was two: what it is speaking,
     * what kind of speaker it is, and how to end it. Every one is read-only or an ending.
     * Anything wider would invite the arbiter to start a session, and starting one needs a
     * `Context`, an engine and a screen's worth of arguments that differ between a narrated
     * file and a voice — which is precisely the difference this type must not know about.
     * [kind] is the one bit of that difference it does know, and only because a requirement
     * names it: it is never dispatched on, only carried into [VoiceStoppedNotice.displacing].
     */
    interface Speaker {

        /** The publication this speaker is speaking, or null when it is silent. */
        val speaking: Spoken?

        /** Which engine this is. Fixed for the life of the speaker: a host speaks one way. */
        val kind: Kind

        /**
         * Ends this speaker's session, writing where it reached before it stops.
         *
         * The order is the requirement, and it is the speaker's to keep: `audio-playback`
         * asks that the position be recorded "before the second begins".
         */
        fun endSpeaking()
    }

    private val speakers = mutableListOf<Speaker>()

    private val _voiceStopped = MutableStateFlow(VoiceStoppedNotice.NONE)

    /**
     * The word a listener is owed because opening a publication stopped their voice.
     *
     * Armed only by [silence] and spent only by [takeVoiceStopped]; the two rules it carries
     * are [VoiceStoppedNotice]'s. A `StateFlow` because the surface that shows it is not the
     * object that armed it, and may not exist yet when the arming happens.
     */
    val voiceStopped: StateFlow<VoiceStoppedNotice> = _voiceStopped.asStateFlow()

    /**
     * Adds a speaker, once.
     *
     * Both speakers are Kotlin `object`s that register from their own initialiser, and that
     * is safe for a reason worth stating: an `object` is initialised on first access, and
     * starting a session *is* an access. So a speaker that has not registered has never
     * spoken, and the answers below are complete whichever of the two the app has touched.
     */
    fun register(speaker: Speaker) {
        if (speakers.none { it === speaker }) speakers += speaker
    }

    /** The publication being spoken, whichever engine is speaking it. */
    val speaking: String? get() = speakers.firstNotNullOfOrNull { it.speaking?.id }

    /**
     * Asks the question and acts on the answer, which is what a caller about to start wants.
     *
     * What opening a publication *means* stays [SessionHandover.opening]'s, so there is one
     * copy of that rule and both platforms read it. What this adds is the one thing a value
     * over two ids cannot know: **which** speaker holds the session, and only that speaker
     * may adopt it. A reader cannot pick up a narrator's cursor and a narrator has no
     * sentence to hand a reader, so anything else holding the same publication is a
     * displacement like any other. iOS reaches the same guard from the other end —
     * `prepareReadAloud` asks the player for the handover and then re-checks that it is the
     * *voice* which holds the book before adopting.
     *
     * On [SessionHandover.DISPLACE] everything speaking has already stopped by the time this
     * returns, so the caller's next line may make a sound.
     */
    fun claim(publication: String, by: Speaker): SessionHandover {
        val answer = when (SessionHandover.opening(publication, speaking)) {
            SessionHandover.NONE -> SessionHandover.NONE
            SessionHandover.ADOPT ->
                if (isHeldOnlyBy(by)) SessionHandover.ADOPT else SessionHandover.DISPLACE
            SessionHandover.DISPLACE -> SessionHandover.DISPLACE
        }
        if (answer == SessionHandover.DISPLACE) silence(toSpeak = publication)
        return answer
    }

    private fun isHeldOnlyBy(speaker: Speaker): Boolean =
        speakers.none { it !== speaker && it.speaking != null }

    /**
     * Everything speaking stops, and each writes where it reached first.
     *
     * What a `begin` that always starts a fresh session calls, which is iOS's
     * `PlayerCentre.begin` ending the outgoing book before it touches the incoming one. Held
     * apart from [claim] because the two callers mean different things: one is asking
     * whether to start at all, the other has already decided.
     *
     * **This is the displacement, so this is where the word is armed.** Of the ways a session
     * ends — the listener's stop, the book running out, audio taken for good — only this one
     * reaches [Speaker.endSpeaking], and only a [Kind.VOICE] leaves a pending notice; see
     * [VoiceStoppedNotice]. Armed before the ending, so it is standing by the time the screen
     * that caused it asks. Only a pending notice is written: a narrator displaced while a
     * voice's word is still owed does not take that word away.
     *
     * @param toSpeak the publication about to speak, when known. A speaker restarting the same
     *   publication is not displaced by it — nothing went quiet that the listener is not
     *   looking at — so it is silenced and owes nothing. iOS's `begin` draws the same line.
     */
    fun silence(toSpeak: String? = null) {
        // Over a copy: ending a session is what makes a speaker go silent, and a speaker is
        // free to tear another one down while it does.
        speakers.toList().forEach { speaker ->
            val spoken = speaker.speaking ?: return@forEach
            if (spoken.id != toSpeak) {
                val owed = VoiceStoppedNotice.displacing(
                    aVoice = speaker.kind == Kind.VOICE,
                    title = spoken.title,
                )
                if (owed.isPending) _voiceStopped.value = owed
            }
            speaker.endSpeaking()
        }
    }

    /**
     * The notice, given to the surface that asked — and spent by the asking.
     *
     * Returns what was owed and leaves [voiceStopped] at [VoiceStoppedNotice.NONE], which is
     * the whole of *once*: the EPUB reader that displaced a voice takes it as its page opens,
     * the player that an audiobook opened onto takes it as it is drawn, and a return to either
     * finds nothing to say.
     */
    fun takeVoiceStopped(): VoiceStoppedNotice {
        val owed = _voiceStopped.value
        _voiceStopped.value = owed.taken()
        return owed
    }

    companion object {

        /**
         * The one in the app's process.
         *
         * A singleton for the reason `PlaybackHost` and `ReadAloudHost` are: the question
         * "may this source start" has to be answered by something that outlives every
         * screen, and no screen's state has that lifetime.
         */
        val shared = SpokenAudio()
    }
}
