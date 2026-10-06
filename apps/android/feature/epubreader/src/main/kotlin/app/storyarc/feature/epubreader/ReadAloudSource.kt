package app.storyarc.feature.epubreader

import app.storyarc.core.model.TotalProgression
import app.storyarc.core.playback.PlaybackPart
import app.storyarc.core.playback.PlaybackPosition
import app.storyarc.core.playback.PlaybackSession
import app.storyarc.core.playback.PlaybackSpeed
import app.storyarc.core.playback.PlayerSource
import app.storyarc.core.playback.SkipDirection
import app.storyarc.core.playback.SkipUnit

/**
 * The synthesised voice, as one of the player's two sources.
 *
 * **This is what makes `audio-playback`'s "both sources look the same" structural rather
 * than promised.** The requirement is that "the surface, the controls and the lock-screen
 * presentation are the same" whichever produced the sound, and the answer is one interface
 * with two implementations: `AudiobookSource` decodes a file, this one speaks. Nothing on
 * [PlayerSource] names an engine, so the compact bar and the full player are built from a
 * `NowPlaying` that cannot be asked which is behind it. iOS's `SpokenSource` is the same
 * type in the same place, for the same reason.
 *
 * **It is deliberately thin.** [SpokenSentences] already does the part that is genuinely
 * hard — walking the content across resource boundaries and splitting it into sentences —
 * and [ReadAloudController] says the words. What is here is the translation: a sentence's
 * href into the part the player marks, and the player's transport into the voice's.
 *
 * **The two places the sources genuinely differ, and both are declared as data.** Its parts
 * carry no duration, because a voice does not know how long it will speak; and its
 * [skipUnit] is [SkipUnit.SENTENCE], because a voice has no seconds to move by. The player
 * reads both and draws accordingly — no scrub control, no clock, no *end of chapter*, and a
 * skip labelled in sentences — which is "every control the player offers works, or is
 * absent — none is present and refusing", enforced without anything asking what is playing.
 */
internal class ReadAloudSource(
    private val voice: SpokenVoice,
    private val book: SpokenBook,
    override val parts: List<PlaybackPart>,
    /** The reading order by href, which is what turns a sentence's locator into a part. */
    private val readingOrder: List<String>,
    openingAt: Int = 0,
) : PlayerSource {

    override val publicationId: String get() = book.id

    override val title: String get() = book.title

    /** One sentence, which is all a synthesised voice can offer. See [SkipUnit]. */
    override val skipUnit: SkipUnit = SkipUnit.SENTENCE

    private var partIndex: Int = openingAt.coerceAtLeast(0)

    /**
     * Which resource the voice is inside, and nothing finer.
     *
     * The offset is always zero, and that is the honest answer rather than a placeholder: a
     * voice has no clock, so there is no time into the chapter to report. Every surface that
     * would divide by a part's length asks [PlaybackPart.duration] first and finds
     * `Unknown`, so none of them divides by anything.
     */
    override val position: PlaybackPosition get() = PlaybackPosition(partIndex, 0)

    override val session: PlaybackSession get() = voice.session.value

    override var speed: PlaybackSpeed = PlaybackSpeed.NORMAL
        private set

    override var onChange: (() -> Unit)? = null

    /**
     * Set by `PlaybackCentre` and never invoked here, because the voice answers its own
     * interruption.
     *
     * [ReadAloudController] holds the audio-focus request, so it is told first and it asks
     * [PlaybackSession.endingInterruption] itself — the same table the centre would have
     * asked. The outcomes reach the surface the same way everything else does: through the
     * session this source reports.
     */
    override var onInterruptionEnd: ((mayResume: Boolean) -> Unit)? = null

    // MARK: - The transport

    /**
     * Play and pause, expressed as the one verb the voice has.
     *
     * [SpokenVoice.toggle] is what the reader's own control, the notification and the lock
     * screen have always called, and it already decides what a resume means for a session
     * that was interrupted rather than paused. Asking it only when the state has to change
     * is what keeps a second press of play from pausing the book.
     */
    override fun play() {
        if (!session.isPlaying) voice.toggle()
    }

    override fun pause() {
        if (session.isPlaying) voice.toggle()
    }

    override fun stop() = voice.stop()

    /**
     * Moves to the start of a chapter, which for a voice is the start of a resource.
     *
     * The offset is dropped rather than approximated: there is no clock to land on. This is
     * also what [seekToPart]'s default calls, so choosing a chapter from the player's list
     * and seeking arrive at the same place.
     */
    override fun seek(to: PlaybackPosition) {
        if (to.partIndex !in readingOrder.indices) return
        partIndex = to.partIndex
        voice.jumpTo(to.partIndex)
        onChange?.invoke()
    }

    /**
     * One sentence, whatever interval the centre offers.
     *
     * The interval is ignored and [skipUnit] is why: the player states *sentence* on the
     * control rather than a number of seconds, so there is no distance here to honour.
     */
    override fun skip(direction: SkipDirection, byMillis: Long) {
        voice.skip(forward = direction == SkipDirection.FORWARD)
    }

    override fun setSpeed(speed: PlaybackSpeed) {
        this.speed = speed
        voice.setSpeed(speed.rate)
        onChange?.invoke()
    }

    /**
     * The sleep timer's ending, kept at a place a listener would not notice being cut off at.
     *
     * A voice has no gain to fade, so `audio-playback`'s "fades out rather than cutting off"
     * is kept the only way a sentence can keep it: the one being said is finished, and the
     * next is not begun.
     */
    override fun stopAtSentenceEnd() = voice.stopAtSentenceEnd()

    // MARK: - What the session reports back

    /**
     * The voice has reached a sentence in [href].
     *
     * Called by [ReadAloudHost] on every sentence, because that is the only thing a voice
     * reports: there is no transition callback to mark a chapter boundary with. A href the
     * reading order does not hold leaves the mark where it was, which is the same answer
     * `TotalProgression.indexOf` gives the percentage line.
     */
    fun reached(href: String) {
        val index = TotalProgression.indexOf(href, readingOrder)
        if (index >= 0) partIndex = index
        onChange?.invoke()
    }

    /** The session changed in a way that is not a sentence: a pause, a resume, an ending. */
    fun refresh() {
        onChange?.invoke()
    }
}
